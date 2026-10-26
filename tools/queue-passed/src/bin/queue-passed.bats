(* queue-passed -- decides whether a push run to main may skip the tests
   because the merge queue already passed the very same commit
   (bats-lang/pwa#215). CI tooling for the queue-passed action: nothing here
   belongs to what pwa generates or to what the app runs. Area keyword:
   queue-passed (.claude/rules/queue-passed.md).

   queue-passed decide <event> <sha> <workflow-ref> <runs-file>

   <event> is the event of the run asking (github.event_name), <sha> its commit
   (github.sha), <workflow-ref> the workflow it runs (github.workflow_ref:
   owner/repo/.github/workflows/check.yml@refs/heads/main) and <runs-file> the
   answer of GitHub's "list workflow runs for a repository" (gh api
   repos/OWNER/REPO/actions/runs?event=merge_group&head_sha=SHA), a file.

   It prints, on stdout, the lines the action appends to GITHUB_OUTPUT:

     skip=true or false
     run-url=<html_url of the queue run that passed, empty when skip is false>
     reason=<one fixed sentence>

   and the same on stderr (a ::notice:: when it skips). skip is true only when
   all of these hold, and a run of everything is the answer to every other case,
   an unreadable file included:

   1. <event> is exactly push (a schedule, a workflow_dispatch, a pull_request
      and a merge_group run never skip: the nightly cold check of main is the
      check that depends on nothing earlier);
   2. <sha> is 40 lower case hex digits;
   3. the answer holds a run whose event is merge_group, whose head_sha is
      <sha>, whose path is the workflow file of <workflow-ref> (the text
      between its second slash and its @) and whose conclusion is success.
      Each of the four is read from the run itself, so the answer's own
      filters are not trusted: a run of another sha, of another workflow
      file, of another event or with the conclusion failure, cancelled,
      skipped (what the queue's destroyed event ends with, quire#879), or no
      conclusion yet, is no pass.

   Nothing is compared but the sha, the event, the path and the conclusion:
   no time, no name, no cache key. Exit 0 for a call it understood (the
   decision is on stdout), 2 for any other arguments. The answer is read
   whole: at most 1048575 bytes (a bigger one decides run everything), and
   json's parse caps (depth 512, a string of 1 MiB). Every offset carries its
   bounds in its type, so no read is guarded at run time. *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use env as E
#use file as F
#use json as J
#use result as R

(* ============================================================
   Builders and output
   ============================================================ *)

(* text longer than the builder's cap (524288 bytes) is cut there: every text
   here is a path, a URL or a sha, far shorter *)
fn _put (out: !$B.builder_v >> $B.builder_v, value: int): void =
  if $B.length(out) < 524288 then $B.put_char(out, $AR.low_byte(value)) else ()

fn _bput {text_size:nat} (out: !$B.builder_v >> $B.builder_v, text: string text_size): void = let
  fun loop {text_size:nat}{i:nat | i <= text_size} .<text_size - i>.
    (out: !$B.builder_v >> $B.builder_v, text: string text_size, size: int text_size, i: int i): void =
    if i >= size then ()
    else let
      val () = _put(out, char2int0(string_get_at(text, i)))
    in loop(out, text, size, i + 1) end
in loop(out, text, g1u2i(string1_length(text)), 0) end

(* a builder holding the text *)
fn _builder_of {text_size:nat} (text: string text_size): $B.builder_v = let
  var out : $B.builder_v = $B.create()
  val () = _bput(out, text)
in out end

(* bytes[start, stop) appended to out *)
fun _put_range {l:agz}{size:pos}{start:nat}{stop:int | start <= stop; stop <= size} .<stop - start>.
  (bytes: !$A.borrow(byte, l, size), start: int start, stop: int stop, size: int size,
   out: !$B.builder_v >> $B.builder_v): void =
  if start >= stop then ()
  else let
    val () = _put(out, byte2int0($A.read<byte>(bytes, start)))
  in _put_range(bytes, start + 1, stop, size, out) end

(* a decoded JSON string's first length bytes appended to out *)
fun _put_text {l:agz}{capacity:pos}{length:nat | length <= capacity}{i:nat | i <= length} .<length - i>.
  (bytes: !$A.borrow(byte, l, capacity), length: int length, i: int i,
   out: !$B.builder_v >> $B.builder_v): void =
  if i >= length then ()
  else let
    val () = _put(out, byte2int0($A.read<byte>(bytes, i)))
  in _put_text(bytes, length, i + 1, out) end

(* the builder's bytes to stdout (when to_error is false) or stderr; consumed *)
fn _emit (message: $B.builder_v, to_error: bool): void = let
  val @(array, size) = $B.to_arr(message)
  val @(frozen, view) = $A.freeze<byte>(array)
  fun loop {l:agz}{i:nat}{size:nat | i <= size; size <= 524288} .<size - i>.
    (view: !$A.borrow(byte, l, 524288), i: int i, size: int size, to_error: bool): void =
    if i >= size then ()
    else let
      val letter = int2char0(byte2int0($A.read<byte>(view, i)))
      val () = (if to_error then prerr_char(letter) else print_char(letter))
    in loop(view, i + 1, size, to_error) end
  val () = loop(view, 0, size, to_error)
  val () = $A.drop<byte>(frozen, view)
in $A.free<byte>($A.thaw<byte>(frozen)) end

fn _say_text {text_size:nat} (text: string text_size): void = _emit(_builder_of(text), true)

(* ============================================================
   Comparing texts
   ============================================================ *)

(* the first n bytes of the two borrows are the same *)
fun _equal {la,lb:agz}{ca,cb:pos}{n:nat | n <= ca; n <= cb}{i:nat | i <= n} .<n - i>.
  (a: !$A.borrow(byte, la, ca), b: !$A.borrow(byte, lb, cb), n: int n, i: int i): bool =
  if i >= n then true
  else if byte2int0($A.read<byte>(a, i)) <> byte2int0($A.read<byte>(b, i)) then false
  else _equal(a, b, n, i + 1)

(* whether the two builders hold the same bytes; both consumed *)
fn _same_text (first: $B.builder_v, second: $B.builder_v): bool = let
  val @(first_array, first_size) = $B.to_arr(first)
  val @(second_array, second_size) = $B.to_arr(second)
  val @(first_frozen, first_view) = $A.freeze<byte>(first_array)
  val @(second_frozen, second_view) = $A.freeze<byte>(second_array)
  val same = (if first_size = second_size
    then _equal(first_view, second_view, first_size, 0) else false): bool
  val () = $A.drop<byte>(first_frozen, first_view)
  val () = $A.drop<byte>(second_frozen, second_view)
  val () = $A.free<byte>($A.thaw<byte>(first_frozen))
  val () = $A.free<byte>($A.thaw<byte>(second_frozen))
in same end

(* ============================================================
   What a JSON value is, once
   ============================================================ *)

(* A value as the decision sees it: an object, an array, a string (decoded,
   cut at the builder's cap) or anything else. The one place that lists every
   kind of json value. *)
datavtype shape =
  | shape_object of ([size:nat] $J.json_entries(size))
  | shape_array of ([size:nat] $J.json_list(size))
  | shape_text of ($B.builder_v)
  | shape_other of ()

fn _shape (value: $J.json_v): shape =
  case+ value of
  | ~$J.json_null() => shape_other()
  | ~$J.json_bool(_) => shape_other()
  | ~$J.json_num(number, _, parsed) => let
      val () = $R.option_discard<int>(parsed)
      val () = $A.free<byte>(number)
    in shape_other() end
  | ~$J.json_str(text, length) => let
      var out : $B.builder_v = $B.create()
      val @(frozen, view) = $A.freeze<byte>(text)
      val () = _put_text(view, length, 0, out)
      val () = $A.drop<byte>(frozen, view)
      val () = $A.free<byte>($A.thaw<byte>(frozen))
    in shape_text(out) end
  | ~$J.json_arr(items) => shape_array(items)
  | ~$J.json_obj(entries) => shape_object(entries)

(* what a shape holds, freed *)
fn _shape_free (value: shape): void =
  case+ value of
  | ~shape_object(entries) => $J.json_entries_free(entries)
  | ~shape_array(items) => $J.json_list_free(items)
  | ~shape_text(text) => $B.builder_free(text)
  | ~shape_other() => ()

(* the value's text when it is a string, else an empty text; the value consumed *)
fn _text_of (value: $J.json_v): $B.builder_v =
  case+ _shape(value) of
  | ~shape_text(text) => text
  | other => let
      val () = _shape_free(other)
    in $B.create() end

(* whether the value is a string that is exactly expected; both consumed *)
fn _text_is (value: $J.json_v, expected: $B.builder_v): bool =
  _same_text(_text_of(value), expected)

(* ============================================================
   A key of an object
   ============================================================ *)

(* the first length bytes of the borrow are exactly the literal *)
fn _literal_equal {l:agz}{capacity:pos}{length:nat | length <= capacity}{literal_size:nat}
  (bytes: !$A.borrow(byte, l, capacity), length: int length, literal: string literal_size): bool = let
  val literal_length = g1u2i(string1_length(literal))
  fun loop {literal_size:nat}{j:nat | j <= literal_size} .<literal_size - j>.
    (bytes: !$A.borrow(byte, l, capacity), length: int length, literal: string literal_size,
     literal_length: int literal_size, j: int j): bool =
    if j >= literal_length then true
    else if j >= length then false
    else if byte2int0($A.read<byte>(bytes, j)) <> char2int0(string_get_at(literal, j)) then false
    else loop(bytes, length, literal, literal_length, j + 1)
in length = literal_length && loop(bytes, length, literal, literal_length, 0) end

(* Which member of a workflow run a key names: 1 event, 2 head_sha, 3 path,
   4 conclusion, 5 html_url, 0 none of them; the key consumed *)
fn _member {l:agz}{capacity:pos}{length:nat | length <= capacity}
  (key: $A.arr(byte, l, capacity), length: int length): int = let
  val @(frozen, view) = $A.freeze<byte>(key)
  val member = (if _literal_equal(view, length, "event") then 1
    else if _literal_equal(view, length, "head_sha") then 2
    else if _literal_equal(view, length, "path") then 3
    else if _literal_equal(view, length, "conclusion") then 4
    else if _literal_equal(view, length, "html_url") then 5
    else 0): int
  val () = $A.drop<byte>(frozen, view)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in member end

(* whether the key is exactly the literal; the key consumed *)
fn _key_is {l:agz}{capacity:pos}{length:nat | length <= capacity}{literal_size:nat}
  (key: $A.arr(byte, l, capacity), length: int length, literal: string literal_size): bool = let
  val @(frozen, view) = $A.freeze<byte>(key)
  val same = _literal_equal(view, length, literal)
  val () = $A.drop<byte>(frozen, view)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in same end

(* ============================================================
   The runs
   ============================================================ *)

(* The arguments' bytes [start, stop) as a builder *)
fn _range_text {l:agz}{start:nat}{stop:int | start <= stop; stop <= 4096}
  (arguments: !$A.borrow(byte, l, 4096), start: int start, stop: int stop): $B.builder_v = let
  var out : $B.builder_v = $B.create()
  val () = _put_range(arguments, start, stop, 4096, out)
in out end

(* The members of one workflow run, from its entries: a pass when its event is
   merge_group, its head_sha the sha (the arguments' [sha_start, sha_stop)), its
   path the workflow's ([path_start, path_stop)) and its conclusion success. The
   html_url is the last one seen. *)
fun _run_entries {size:nat}{l:agz}
  {sha_start:nat}{sha_stop:int | sha_start <= sha_stop; sha_stop <= 4096}
  {path_start:nat}{path_stop:int | path_start <= path_stop; path_stop <= 4096} .<size>.
  (entries: $J.json_entries(size), arguments: !$A.borrow(byte, l, 4096),
   sha_start: int sha_start, sha_stop: int sha_stop, path_start: int path_start, path_stop: int path_stop,
   is_event: bool, is_sha: bool, is_path: bool, is_success: bool, url: $B.builder_v)
  : @(bool, $B.builder_v) =
  case+ entries of
  | ~$J.json_entries_nil() => @(is_event && is_sha && is_path && is_success, url)
  | ~$J.json_entries_cons(key, key_length, value, rest) => let
      val member = _member(key, key_length)
    in
      if member = 1 then _run_entries(rest, arguments, sha_start, sha_stop, path_start, path_stop,
        _text_is(value, _builder_of("merge_group")), is_sha, is_path, is_success, url)
      else if member = 2 then _run_entries(rest, arguments, sha_start, sha_stop, path_start, path_stop,
        is_event, _text_is(value, _range_text(arguments, sha_start, sha_stop)), is_path, is_success, url)
      else if member = 3 then _run_entries(rest, arguments, sha_start, sha_stop, path_start, path_stop,
        is_event, is_sha, _text_is(value, _range_text(arguments, path_start, path_stop)), is_success, url)
      else if member = 4 then _run_entries(rest, arguments, sha_start, sha_stop, path_start, path_stop,
        is_event, is_sha, is_path, _text_is(value, _builder_of("success")), url)
      else if member = 5 then let
        val () = $B.builder_free(url)
      in _run_entries(rest, arguments, sha_start, sha_stop, path_start, path_stop,
        is_event, is_sha, is_path, is_success, _text_of(value)) end
      else let
        val () = $J.json_free(value)
      in _run_entries(rest, arguments, sha_start, sha_stop, path_start, path_stop,
        is_event, is_sha, is_path, is_success, url) end
    end

(* Whether the value is a run that passed, and its url *)
fn _run {l:agz}
  {sha_start:nat}{sha_stop:int | sha_start <= sha_stop; sha_stop <= 4096}
  {path_start:nat}{path_stop:int | path_start <= path_stop; path_stop <= 4096}
  (value: $J.json_v, arguments: !$A.borrow(byte, l, 4096),
   sha_start: int sha_start, sha_stop: int sha_stop, path_start: int path_start, path_stop: int path_stop)
  : @(bool, $B.builder_v) =
  case+ _shape(value) of
  | ~shape_object(entries) => _run_entries(entries, arguments, sha_start, sha_stop, path_start, path_stop,
      false, false, false, false, $B.create())
  | other => let
      val () = _shape_free(other)
    in @(false, $B.create()) end

(* The first run of the list that passed, and its url *)
fun _runs {size:nat}{l:agz}
  {sha_start:nat}{sha_stop:int | sha_start <= sha_stop; sha_stop <= 4096}
  {path_start:nat}{path_stop:int | path_start <= path_stop; path_stop <= 4096} .<size>.
  (items: $J.json_list(size), arguments: !$A.borrow(byte, l, 4096),
   sha_start: int sha_start, sha_stop: int sha_stop, path_start: int path_start, path_stop: int path_stop)
  : @(bool, $B.builder_v) =
  case+ items of
  | ~$J.json_list_nil() => @(false, $B.create())
  | ~$J.json_list_cons(value, rest) => let
      val @(passed, url) = _run(value, arguments, sha_start, sha_stop, path_start, path_stop)
    in
      if passed then let
        val () = $J.json_list_free(rest)
      in @(true, url) end
      else let
        val () = $B.builder_free(url)
      in _runs(rest, arguments, sha_start, sha_stop, path_start, path_stop) end
    end

(* The members of the answer: its workflow_runs array is the runs *)
fun _answer {size:nat}{l:agz}
  {sha_start:nat}{sha_stop:int | sha_start <= sha_stop; sha_stop <= 4096}
  {path_start:nat}{path_stop:int | path_start <= path_stop; path_stop <= 4096} .<size>.
  (entries: $J.json_entries(size), arguments: !$A.borrow(byte, l, 4096),
   sha_start: int sha_start, sha_stop: int sha_stop, path_start: int path_start, path_stop: int path_stop)
  : @(bool, $B.builder_v) =
  case+ entries of
  | ~$J.json_entries_nil() => @(false, $B.create())
  | ~$J.json_entries_cons(key, key_length, value, rest) =>
    if _key_is(key, key_length, "workflow_runs") then
      (case+ _shape(value) of
       | ~shape_array(items) => let
           val @(passed, url) = _runs(items, arguments, sha_start, sha_stop, path_start, path_stop)
         in
           if passed then let
             val () = $J.json_entries_free(rest)
           in @(true, url) end
           else let
             val () = $B.builder_free(url)
           in _answer(rest, arguments, sha_start, sha_stop, path_start, path_stop) end
         end
       | other => let
           val () = _shape_free(other)
         in _answer(rest, arguments, sha_start, sha_stop, path_start, path_stop) end)
    else let
      val () = $J.json_free(value)
    in _answer(rest, arguments, sha_start, sha_stop, path_start, path_stop) end

(* ============================================================
   The arguments and the file
   ============================================================ *)

(* The process's arguments, NUL-separated, into buffer: their length *)
fn _arguments_read {l:agz} (buffer: !$A.arr(byte, l, 4096)): [size:nat | size <= 4096] int size =
  case+ $E.args_read(buffer, 4096) of
  | ~$R.some(size) => size
  | ~$R.none() => 0

(* Where the argument starting at start ends (its NUL), within size *)
fun _argument_end {l:agz}{start:nat}{size:nat | start <= size; size <= 4096} .<size - start>.
  (bytes: !$A.borrow(byte, l, 4096), start: int start, size: int size)
  : [stop:nat | start <= stop; stop <= size] int stop =
  if start >= size then start
  else if byte2int0($A.read<byte>(bytes, start)) = 0 then start
  else _argument_end(bytes, start + 1, size)

(* Where the arguments from start on, count of them skipped, begin *)
fun _skip_arguments {l:agz}{size:nat | size <= 4096}{start:nat | start <= size}{count:nat} .<count>.
  (bytes: !$A.borrow(byte, l, 4096), size: int size, start: int start, count: int count)
  : [place:nat | start <= place; place <= size] int place =
  if count <= 0 then start
  else let
    val stop = _argument_end(bytes, start, size)
  in
    if stop >= size then size else _skip_arguments(bytes, size, stop + 1, count - 1)
  end

(* The argument at index (the program is 0): [start, stop), at size when absent *)
fn _argument_range {l:agz}{size:nat | size <= 4096}{index:nat}
  (bytes: !$A.borrow(byte, l, 4096), size: int size, index: int index)
  : [start,stop:nat | start <= stop; stop <= size] @(int start, int stop) = let
  val start = _skip_arguments(bytes, size, 0, index)
  val stop = _argument_end(bytes, start, size)
in @(start, stop) end

(* Whether bytes[start, stop) is exactly literal *)
fn _is {l:agz}{start:nat}{stop:int | start <= stop; stop <= 4096}{literal_size:nat}
  (bytes: !$A.borrow(byte, l, 4096), start: int start, stop: int stop, literal: string literal_size): bool = let
  val literal_length = g1u2i(string1_length(literal))
  fun loop {literal_size:nat}{j:nat | j <= literal_size} .<literal_size - j>.
    (bytes: !$A.borrow(byte, l, 4096), start: int start, stop: int stop,
     literal: string literal_size, literal_length: int literal_size, j: int j): bool =
    if j >= literal_length then true
    else if start + j >= stop then false
    else if byte2int0($A.read<byte>(bytes, start + j)) <> char2int0(string_get_at(literal, j)) then false
    else loop(bytes, start, stop, literal, literal_length, j + 1)
in stop - start = literal_length && loop(bytes, start, stop, literal, literal_length, 0) end

(* Whether bytes[start, stop) is 40 digits of 0 to 9 and a to f *)
fn _is_sha {l:agz}{start:nat}{stop:int | start <= stop; stop <= 4096}
  (bytes: !$A.borrow(byte, l, 4096), start: int start, stop: int stop): bool = let
  fun loop {j:nat | j <= 40} .<40 - j>.
    (bytes: !$A.borrow(byte, l, 4096), start: int start, stop: int stop, j: int j): bool =
    if j >= 40 then true
    else if start + j >= stop then false
    else let
      val letter = byte2int0($A.read<byte>(bytes, start + j))
    in
      if (letter >= 48 && letter <= 57) || (letter >= 97 && letter <= 102)
      then loop(bytes, start, stop, j + 1) else false
    end
in stop - start = 40 && loop(bytes, start, stop, 0) end

(* The first place in [start, stop) holding the byte, else stop *)
fun _find {l:agz}{start:nat}{stop:int | start <= stop; stop <= 4096} .<stop - start>.
  (bytes: !$A.borrow(byte, l, 4096), start: int start, stop: int stop, wanted: int)
  : [place:nat | start <= place; place <= stop] int place =
  if start >= stop then start
  else if byte2int0($A.read<byte>(bytes, start)) = wanted then start
  else let
    val place = _find(bytes, start + 1, stop, wanted)
  in place end

(* The workflow file of a workflow ref (owner/repo/path@ref): the bytes after its
   second slash, up to its @; empty when there is no second slash *)
fn _workflow_path {l:agz}{start:nat}{stop:int | start <= stop; stop <= 4096}
  (bytes: !$A.borrow(byte, l, 4096), start: int start, stop: int stop)
  : [first,last:nat | first <= last; last <= stop] @(int first, int last) = let
  val first_slash = _find(bytes, start, stop, 47)
in
  if first_slash >= stop then @(stop, stop)
  else let
    val second_slash = _find(bytes, first_slash + 1, stop, 47)
  in
    if second_slash >= stop then @(stop, stop)
    else let
      val path_stop = _find(bytes, second_slash + 1, stop, 64)
    in @(second_slash + 1, path_stop) end
  end
end

(* ============================================================
   The decision
   ============================================================ *)

(* The decision, said: skip=, run-url= and reason= on stdout, the same sentence
   on stderr (a notice when it skips). The url is consumed. *)
fn _report {reason_size:nat} (skip: bool, url: $B.builder_v, reason: string reason_size): void = let
  val () = (if skip then print_string("skip=true\n") else print_string("skip=false\n"))
  val () = print_string("run-url=")
  val () = _emit(url, false)
  val () = print_string("\nreason=")
  val () = print_string(reason)
  val () = print_string("\n")
  val () = (if skip then _say_text("::notice title=queue-passed::") else _say_text("queue-passed: "))
  val () = _say_text(reason)
  val () = _say_text("\n")
in () end

(* The answer in the n bytes of the borrow, parsed and searched for a run that passed *)
fn _search {l:agz}{n:pos}{al:agz}
  {sha_start:nat}{sha_stop:int | sha_start <= sha_stop; sha_stop <= 4096}
  {path_start:nat}{path_stop:int | path_start <= path_stop; path_stop <= 4096}
  (answer: !$A.borrow(byte, l, n), size: int n, arguments: !$A.borrow(byte, al, 4096),
   sha_start: int sha_start, sha_stop: int sha_stop, path_start: int path_start, path_stop: int path_stop): void =
  case+ $J.parse_text(answer, size) of
  | ~$R.err(error) => let
      val _ = $J.parse_error_pos(error)
    in _report(false, $B.create(), "the runs answer is not JSON") end
  | ~$R.ok(root) => (case+ _shape(root) of
    | ~shape_object(entries) => let
        val @(passed, url) = _answer(entries, arguments, sha_start, sha_stop, path_start, path_stop)
      in
        if passed then _report(true, url, "the merge queue passed this commit in the run named in run-url")
        else let
          val () = $B.builder_free(url)
        in _report(false, $B.create(),
          "no successful merge_group run of this workflow on this sha in the answer") end
      end
    | other => let
        val () = _shape_free(other)
      in _report(false, $B.create(), "the runs answer is not a JSON object") end)

(* The file at path read whole, an array of exactly its size (1 to 1048576 bytes),
   and searched. Any other file, or one that cannot be read, is said and decides
   run everything. The path is consumed. *)
fn _decide_file {l:agz}
  {sha_start:nat}{sha_stop:int | sha_start <= sha_stop; sha_stop <= 4096}
  {path_start:nat}{path_stop:int | path_start <= path_stop; path_stop <= 4096}
  (path: $B.builder_v, arguments: !$A.borrow(byte, l, 4096),
   sha_start: int sha_start, sha_stop: int sha_stop, path_start: int path_start, path_stop: int path_stop): void = let
  val () = _put(path, 0)
  val @(path_array, _) = $B.to_arr(path)
  val @(frozen_path, path_borrow) = $A.freeze<byte>(path_array)
  val () = (case+ $F.file_open(path_borrow, 524288, $F.ReadOnly(), $F.OpenExisting(), 0) of
    | ~$R.err(_) => _report(false, $B.create(), "the runs answer cannot be opened")
    | ~$R.ok(fd) => let
        val file_size = (case+ $F.fd_size(fd) of
          | ~$R.ok(size) => size
          | ~$R.err(_) => ~1): [file_size:int | ~1 <= file_size] int file_size
        val () = (if file_size < 1 then
            _report(false, $B.create(), "the runs answer is empty or its size cannot be read")
          else if file_size > 1048576 then
            _report(false, $B.create(), "the runs answer is over 1048576 bytes")
          else let
            val buffer = $A.alloc<byte>(file_size)
            val count = (case+ $F.file_read(fd, buffer, file_size) of
              | ~$R.ok(count) => count
              | ~$R.err(_) => ~1): [count:int] int count
            val @(frozen, view) = $A.freeze<byte>(buffer)
            val () = (if count = file_size
              then _search(view, file_size, arguments, sha_start, sha_stop, path_start, path_stop)
              else _report(false, $B.create(), "the runs answer cannot be read whole"))
            val () = $A.drop<byte>(frozen, view)
          in $A.free<byte>($A.thaw<byte>(frozen)) end)
      in $R.discard<int><$F.io_error>($F.file_close(fd)) end)
  val () = $A.drop<byte>(frozen_path, path_borrow)
in $A.free<byte>($A.thaw<byte>(frozen_path)) end

implement main0 () = let
  val arguments = $A.alloc<byte>(4096)
  val size = _arguments_read(arguments)
  val @(frozen, view) = $A.freeze<byte>(arguments)
  val @(command_start, command_stop) = _argument_range(view, size, 1)
  val @(event_start, event_stop) = _argument_range(view, size, 2)
  val @(sha_start, sha_stop) = _argument_range(view, size, 3)
  val @(ref_start, ref_stop) = _argument_range(view, size, 4)
  val @(file_start, file_stop) = _argument_range(view, size, 5)
  val @(extra_start, _) = _argument_range(view, size, 6)
  val usable = (size < 4095 && _is(view, command_start, command_stop, "decide")
    && file_stop > file_start && extra_start >= size): bool
  val status = (if ~usable then let
      val () = _say_text("usage: queue-passed decide EVENT SHA WORKFLOW-REF RUNS-FILE\n")
    in 2 end
    else let
      val @(path_start, path_stop) = _workflow_path(view, ref_start, ref_stop)
      val () = (if ~_is(view, event_start, event_stop, "push") then
          _report(false, $B.create(), "the event is not push: everything runs")
        else if ~_is_sha(view, sha_start, sha_stop) then
          _report(false, $B.create(), "the commit is not 40 lower case hex digits: everything runs")
        else if path_stop <= path_start then
          _report(false, $B.create(), "the workflow ref is not owner/repo/path@ref: everything runs")
        else _decide_file(_range_text(view, file_start, file_stop), view, sha_start, sha_stop, path_start, path_stop))
    in 0 end): int
  val () = $A.drop<byte>(frozen, view)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in (if status <> 0 then exit_void(status) else ()) end
