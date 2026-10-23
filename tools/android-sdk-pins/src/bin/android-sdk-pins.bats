(* android-sdk-pins -- installs the Android SDK packages the smoke test
   runs on at the revisions pins.txt names, each from a download checked
   against the SHA-1 of Google's repository XML (bats-lang/pwa#137). CI
   tooling for android.yml: nothing here is part of what pwa generates or
   of what the app runs. Area keyword: android-smoke (.claude/rules/android-smoke.md).

   android-sdk-pins install <sdk-root>
   android-sdk-pins key

   key prints the SHA-256 of pins.txt (64 lower case hex digits and a newline,
   from sha256sum) on stdout: the digest that android.yml's system-image cache
   key ends with, so a pin that moves is a new key (bats-lang/pwa#138;
   tests/android-sdk-pins/check.sh, the key cases). Exit 0, or 2 when pins.txt
   cannot be read.

   install runs in the directory that holds pins.txt and the packages' package.xml
   files. A line of pins.txt is five words separated by single spaces:

     <name> <url> <sha1> <unzip-into> <package-dir>

   (<unzip-into> and <package-dir> are relative to <sdk-root>; lines that
   are empty or start with # are skipped), and <name>.xml is the package.xml
   that sdkmanager writes for that package. For each line:

   1. The package is as pinned when <package-dir>/package.xml is the very
      bytes of <name>.xml (cmp): nothing is downloaded. sdkmanager, which
      reads that file, then sees the pinned revision as installed.
   2. Else the zip is downloaded with curl (its own retries on a dropped
      connection), and its SHA-1 (sha1sum) must be the pin's. A mismatch
      is not installed: the zip is removed and the download tried again, up
      to ANDROID_SDK_PINS_ATTEMPTS times (default 3, 1 to 10) with a pause
      that doubles from ANDROID_SDK_PINS_PAUSE_S seconds (default 15, 0 to
      3600); after the last the run fails, naming both sums.
   3. <package-dir> is removed, the zip unpacked into <unzip-into>, and
      <name>.xml copied to <package-dir>/package.xml.

   Exit 0: every package is as pinned. 1: one is not (said on stderr, the
   packages before it stay installed). 2: the arguments or pins.txt are
   not usable. pins.txt may hold at most 65535 bytes, the arguments 4095.
   Every offset into the pins file or the arguments carries its bounds in its
   type (a token is [start, stop) with start <= stop <= its line's end <= the
   file's size <= 65535), so no read is guarded at run time. *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use env as E
#use file as F
#use list as L
#use process as P
#use result as R

(* ============================================================
   Builders and arguments
   ============================================================ *)

(* text longer than the builder's cap (524288 bytes) is cut there: every text
   here is a path, a URL or a message, far shorter *)
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

(* number in decimal *)
fun _put_int {number:nat} .<number>. (out: !$B.builder_v >> $B.builder_v, number: int number): void =
  if number < 10 then _put(out, 48 + number)
  else let
    val () = _put_int(out, number / 10)
  in _put(out, 48 + (number - (number / 10) * 10)) end

(* bytes[start, stop) appended to out *)
fun _put_range {l:agz}{size:pos}{start:nat}{stop:int | start <= stop; stop <= size} .<stop - start>.
  (bytes: !$A.borrow(byte, l, size), start: int start, stop: int stop, size: int size,
   out: !$B.builder_v >> $B.builder_v): void =
  if start >= stop then ()
  else let
    val () = _put(out, byte2int0($A.read<byte>(bytes, start)))
  in _put_range(bytes, start + 1, stop, size, out) end

fn _argument (text: $B.builder_v): $P.arg_entry = let
  val @(array, size) = $B.into_arr(text)
in @(array, size) end

fn _argument_of {text_size:nat} (text: string text_size): $P.arg_entry = let
  var out : $B.builder_v = $B.create()
  val () = _bput(out, text)
in _argument(out) end

(* the pins file's bytes [start, stop) as an argument *)
fn _argument_token {pins_loc:agz}{start:nat}{stop:int | start <= stop; stop <= 65536}
  (pins_borrow: !$A.borrow(byte, pins_loc, 65536), start: int start, stop: int stop): $P.arg_entry = let
  var out : $B.builder_v = $B.create()
  val () = _put_range(pins_borrow, start, stop, 65536, out)
in _argument(out) end

(* the pins file's bytes [start, stop), then after *)
fn _argument_token_then {pins_loc:agz}{start:nat}{stop:int | start <= stop; stop <= 65536}{after_size:nat}
  (pins_borrow: !$A.borrow(byte, pins_loc, 65536), start: int start, stop: int stop,
   after: string after_size): $P.arg_entry = let
  var out : $B.builder_v = $B.create()
  val () = _put_range(pins_borrow, start, stop, 65536, out)
  val () = _bput(out, after)
in _argument(out) end

(* the SDK root (the arguments' bytes [root_start, root_end)), a slash, then the pins file's bytes [start, stop) *)
fn _argument_root_token {arguments_loc:agz}{pins_loc:agz}
  {root_start:nat}{root_end:int | root_start <= root_end; root_end <= 4096}
  {start:nat}{stop:int | start <= stop; stop <= 65536}
  (arguments_borrow: !$A.borrow(byte, arguments_loc, 4096), root_start: int root_start, root_end: int root_end,
   pins_borrow: !$A.borrow(byte, pins_loc, 65536), start: int start, stop: int stop): $P.arg_entry = let
  var out : $B.builder_v = $B.create()
  val () = _put_range(arguments_borrow, root_start, root_end, 4096, out)
  val () = _put(out, 47)
  val () = _put_range(pins_borrow, start, stop, 65536, out)
in _argument(out) end

(* the SDK root followed by text *)
fn _argument_root_then {arguments_loc:agz}
  {root_start:nat}{root_end:int | root_start <= root_end; root_end <= 4096}{text_size:nat}
  (arguments_borrow: !$A.borrow(byte, arguments_loc, 4096), root_start: int root_start, root_end: int root_end,
   text: string text_size): $P.arg_entry = let
  var out : $B.builder_v = $B.create()
  val () = _put_range(arguments_borrow, root_start, root_end, 4096, out)
  val () = _bput(out, text)
in _argument(out) end

fn _arguments2 (first: $P.arg_entry, second: $P.arg_entry): $L.listv($P.arg_entry) =
  $L.list_vt_cons(first, $L.list_vt_cons(second, $L.list_vt_nil()))

fn _arguments3 (first: $P.arg_entry, second: $P.arg_entry, third: $P.arg_entry): $L.listv($P.arg_entry) =
  $L.list_vt_cons(first, _arguments2(second, third))

(* message's bytes to stderr; message consumed *)
fn _say (message: $B.builder_v): void = let
  val @(array, size) = $B.to_arr(message)
  val @(frozen, view) = $A.freeze<byte>(array)
  fun loop {l:agz}{i:nat}{size:nat | i <= size; size <= 524288} .<size - i>.
    (view: !$A.borrow(byte, l, 524288), i: int i, size: int size): void =
    if i >= size then ()
    else let
      val () = prerr_char(int2char0(byte2int0($A.read<byte>(view, i))))
    in loop(view, i + 1, size) end
  val () = loop(view, 0, size)
  val () = $A.drop<byte>(frozen, view)
in $A.free<byte>($A.thaw<byte>(frozen)) end

fn _say_text {text_size:nat} (text: string text_size): void = let
  var message : $B.builder_v = $B.create()
  val () = _bput(message, text)
in _say(message) end

(* before, the pins file's bytes [start, stop), then after, to stderr *)
fn _say_token {pins_loc:agz}{start:nat}{stop:int | start <= stop; stop <= 65536}{before_size,after_size:nat}
  (before: string before_size, pins_borrow: !$A.borrow(byte, pins_loc, 65536),
   start: int start, stop: int stop, after: string after_size): void = let
  var message : $B.builder_v = $B.create()
  val () = _bput(message, before)
  val () = _put_range(pins_borrow, start, stop, 65536, message)
  val () = _bput(message, after)
in _say(message) end

(* ============================================================
   Running a command
   ============================================================ *)

(* bytes[start, size) up to its first newline appended to out *)
fun _put_line {l:agz}{start:nat}{size:nat | start <= size; size <= 4096} .<size - start>.
  (bytes: !$A.borrow(byte, l, 4096), start: int start, size: int size,
   out: !$B.builder_v >> $B.builder_v): void =
  if start >= size then ()
  else let
    val byte_value = byte2int0($A.read<byte>(bytes, start))
  in
    if byte_value = 10 then ()
    else let val () = _put(out, byte_value) in _put_line(bytes, start + 1, size, out) end
  end

(* program (found on PATH) with arguments: the first line of its stdout appended
   to out, and its status (-1 when it could not be run). Its stderr is
   shown; its stdin is empty. *)
fn _run {program_size:nat | program_size < $B.BUILDER_CAP}
  (program: string program_size, arguments: $L.listv($P.arg_entry), out: !$B.builder_v >> $B.builder_v): int = let
  val @(nul_proof | path) = $P.path_of_string_proved(program)
  val @(frozen_path, path_borrow) = $A.barr_freeze(path)
  val argv = $L.list_vt_cons(_argument_of(program), arguments)
  val buffer = $A.alloc<byte>(4096)
  val status = (case+ $P.spawn_inherit_env_proved(nul_proof | path_borrow, argv, $P.dev_null(), $P.pipe_new(), $P.inherit()) of
    | ~$R.ok(spawned) => let
        val+ ~$P.spawn_pipes_mk(child, stdin_pipe, stdout_pipe, stderr_pipe) = spawned
        val () = $P.pipe_end_close(stdin_pipe)
        val () = $P.pipe_end_close(stderr_pipe)
        val+ ~$P.pipe_fd(stdout_fd) = stdout_pipe
        val read_size = (case+ $F.file_read(stdout_fd, buffer, 4096) of
          | ~$R.ok(count) => count | ~$R.err(_) => 0): [count:nat | count <= 4096] int count
        val () = $R.discard<int><$F.io_error>($F.file_close(stdout_fd))
        val exit_code = (case+ $P.child_wait(child) of | ~$R.ok(code) => code | ~$R.err(_) => ~1): int
        val @(frozen_buffer, buffer_borrow) = $A.freeze<byte>(buffer)
        val () = _put_line(buffer_borrow, 0, read_size, out)
        val () = $A.drop<byte>(frozen_buffer, buffer_borrow)
        val () = $A.free<byte>($A.thaw<byte>(frozen_buffer))
      in exit_code end
    | ~$R.err(_) => let
        val () = $A.free<byte>(buffer)
      in ~1 end): int
  val () = $A.cborrow_drop(frozen_path, path_borrow)
  val () = $A.barr_free($A.barr_thaw(frozen_path))
in status end

(* As _run, the output dropped *)
fn _run_quiet {program_size:nat | program_size < $B.BUILDER_CAP}
  (program: string program_size, arguments: $L.listv($P.arg_entry)): int = let
  var ignored : $B.builder_v = $B.create()
  val status = _run(program, arguments, ignored)
  val () = $B.builder_free(ignored)
in status end

(* ============================================================
   The environment, the arguments, the pins file
   ============================================================ *)

fun _fill {text_size:nat}{l:agz}{i:nat | i <= text_size} .<text_size - i>.
  (array: !$A.arr(byte, l, text_size), text: string text_size, size: int text_size, i: int i): void =
  if i >= size then ()
  else let
    val () = $A.set<byte>(array, i, int2byte0(char2int0(string_get_at(text, i))))
  in _fill(array, text, size, i + 1) end

(* The variable name's value appended to out: whether it is set and not empty *)
fn _env {name_size:pos | name_size < 1048576}
  (name: string name_size, out: !$B.builder_v >> $B.builder_v): bool = let
  val name_length = g1u2i(string1_length(name))
  val name_array = $A.alloc<byte>(name_length)
  val () = _fill(name_array, name, name_length, 0)
  val @(frozen_name, name_borrow) = $A.freeze<byte>(name_array)
  val buffer = $A.alloc<byte>(4096)
  val got = $E.get(name_borrow, name_length, buffer, 4096)
  val () = $A.drop<byte>(frozen_name, name_borrow)
  val () = $A.free<byte>($A.thaw<byte>(frozen_name))
  val value_size = (case+ got of | ~$R.some(count) => count | ~$R.none() => 0): [count:nat | count <= 4096] int count
  val @(frozen_buffer, buffer_borrow) = $A.freeze<byte>(buffer)
  val () = _put_range(buffer_borrow, 0, value_size, 4096, out)
  val () = $A.drop<byte>(frozen_buffer, buffer_borrow)
  val () = $A.free<byte>($A.thaw<byte>(frozen_buffer))
in value_size > 0 end

(* The decimal digit c is, or ~1 when it is none *)
fn _digit_of (c: int): [digit:int | ~1 <= digit; digit <= 9] int digit =
  if c = 48 then 0
  else if c = 49 then 1
  else if c = 50 then 2
  else if c = 51 then 3
  else if c = 52 then 4
  else if c = 53 then 5
  else if c = 54 then 6
  else if c = 55 then 7
  else if c = 56 then 8
  else if c = 57 then 9
  else ~1

(* The number the text starts with, or ~1 when it starts with none *)
fn _number_of (text: $B.builder_v): [number:int | ~1 <= number] int number = let
  val @(array, size) = $B.to_arr(text)
  val @(frozen, view) = $A.freeze<byte>(array)
  fun loop {l:agz}{i:nat}{size:nat | i <= size; size <= 524288}{number:int | ~1 <= number} .<size - i>.
    (view: !$A.borrow(byte, l, 524288), i: int i, size: int size, number: int number)
    : [result:int | ~1 <= result] int result =
    if i >= size then number
    else let
      val digit = _digit_of(byte2int0($A.read<byte>(view, i)))
    in
      if digit < 0 then number
      else if number > 100000 then number
      else let
        val base = (if number < 0 then 0 else number): [base:nat | base >= 0] int base
      in loop(view, i + 1, size, base * 10 + digit) end
    end
  val result = loop(view, 0, size, ~1)
  val () = $A.drop<byte>(frozen, view)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in result end

(* The variable's number, else default_value, kept within low and high *)
fn _number_env {name_size:pos | name_size < 1048576}{low,high,default_value:nat | low <= default_value; default_value <= high}
  (name: string name_size, default_value: int default_value, low: int low, high: int high)
  : [number:nat | low <= number; number <= high] int number = let
  var value : $B.builder_v = $B.create()
  val is_set = _env(name, value)
  val number = _number_of(value)
in
  if ~is_set then default_value
  else if number < low then low
  else if number > high then high
  else number
end

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

(* Whether bytes[start, stop) is exactly literal *)
fn _is {literal_size:nat}{l:agz}{size:pos}{start:nat}{stop:int | start <= stop; stop <= size}
  (bytes: !$A.borrow(byte, l, size), start: int start, stop: int stop, literal: string literal_size, size: int size): bool = let
  val literal_length = g1u2i(string1_length(literal))
  fun loop {literal_size:nat}{j:nat | j <= literal_size} .<literal_size - j>.
    (bytes: !$A.borrow(byte, l, size), start: int start, stop: int stop,
     literal: string literal_size, literal_length: int literal_size, j: int j, size: int size): bool =
    if j >= literal_length then true
    else if start + j >= stop then false
    else if byte2int0($A.read<byte>(bytes, start + j)) <> char2int0(string_get_at(literal, j)) then false
    else loop(bytes, start, stop, literal, literal_length, j + 1, size)
in stop - start = literal_length && loop(bytes, start, stop, literal, literal_length, 0, size) end

(* The SDK root, the second argument after "install": its bytes [start, stop)
   of the arguments, empty when the arguments are not "<program> install <root>" *)
fn _root_range {l:agz}{size:nat | size <= 4096}
  (arguments_borrow: !$A.borrow(byte, l, 4096), size: int size)
  : [start:nat][stop:int | start <= stop; stop <= size] @(int start, int stop) = let
  val program_end = _argument_end(arguments_borrow, 0, size)
in
  if program_end >= size then @(0, 0)
  else let
    val command_start = program_end + 1
    val command_end = _argument_end(arguments_borrow, command_start, size)
  in
    if command_end >= size then @(0, 0)
    else if ~_is(arguments_borrow, command_start, command_end, "install", 4096) then @(0, 0)
    else let
      val root_start = command_end + 1
      val root_end = _argument_end(arguments_borrow, root_start, size)
    in @(root_start, root_end) end
  end
end

(* The pins file into buffer and its size: at most 65535 bytes (~1: it cannot
   be read, ~2: it is larger) *)
fn _read_pins {l:agz} (buffer: !$A.arr(byte, l, 65536)): [size:int | ~2 <= size; size <= 65535] int size = let
  var path : $B.builder_v = $B.create()
  val () = _bput(path, "pins.txt")
  val () = _put(path, 0)
  val @(path_array, _) = $B.to_arr(path)
  val @(frozen_path, path_borrow) = $A.freeze<byte>(path_array)
  val result = (case+ $F.file_open(path_borrow, 524288, $F.ReadOnly(), $F.OpenExisting(), 0) of
    | ~$R.err(_) => ~1
    | ~$R.ok(fd) => let
        val file_size = (case+ $F.fd_size(fd) of | ~$R.ok(size) => size | ~$R.err(_) => ~1): [size:int | ~1 <= size] int size
        val size = (if file_size < 0 then ~1
          else if file_size >= 65536 then ~2
          else (case+ $F.file_read(fd, buffer, 65536) of
            | ~$R.ok(count) => (if count = file_size then count else ~1)
            | ~$R.err(_) => ~1)): [size:int | ~2 <= size; size <= 65535] int size
        val () = $R.discard<int><$F.io_error>($F.file_close(fd))
      in size end): [size:int | ~2 <= size; size <= 65535] int size
  val () = $A.drop<byte>(frozen_path, path_borrow)
  val () = $A.free<byte>($A.thaw<byte>(frozen_path))
in result end

(* ============================================================
   One package
   ============================================================ *)

(* The end of the token starting at start: the first space or newline, else limit *)
fun _token_end {l:agz}{start:nat}{limit:nat | start <= limit; limit <= 65536} .<limit - start>.
  (pins_borrow: !$A.borrow(byte, l, 65536), start: int start, limit: int limit)
  : [stop:nat | start <= stop; stop <= limit] int stop =
  if start >= limit then start
  else let
    val byte_value = byte2int0($A.read<byte>(pins_borrow, start))
  in
    if byte_value = 32 then start
    else if byte_value = 10 then start
    else _token_end(pins_borrow, start + 1, limit)
  end

(* The end of the line starting at start: the first newline, else limit *)
fun _line_end {l:agz}{start:nat}{limit:nat | start <= limit; limit <= 65536} .<limit - start>.
  (pins_borrow: !$A.borrow(byte, l, 65536), start: int start, limit: int limit)
  : [stop:nat | start <= stop; stop <= limit] int stop =
  if start >= limit then start
  else if byte2int0($A.read<byte>(pins_borrow, start)) = 10 then start
  else _line_end(pins_borrow, start + 1, limit)

(* Whether the first 40 bytes of the line sha1sum printed (output) are the
   pin's, the bytes [sha_start, sha_stop) of the pins file, and a space follows *)
fn _sha1_is {pins_loc:agz}{sha_start:nat}{sha_stop:int | sha_start <= sha_stop; sha_stop <= 65536}
  (output: $B.builder_v, pins_borrow: !$A.borrow(byte, pins_loc, 65536),
   sha_start: int sha_start, sha_stop: int sha_stop, status: int): bool = let
  val @(array, size) = $B.to_arr(output)
  val @(frozen, view) = $A.freeze<byte>(array)
  fun loop {l:agz}{i:nat | i <= 40}{start:nat | start + 40 <= 65536} .<40 - i>.
    (view: !$A.borrow(byte, l, 524288), pins_borrow: !$A.borrow(byte, pins_loc, 65536),
     i: int i, start: int start): bool =
    if i >= 40 then true
    else if byte2int0($A.read<byte>(view, i)) <> byte2int0($A.read<byte>(pins_borrow, start + i)) then false
    else loop(view, pins_borrow, i + 1, start)
  val same = (if status <> 0 then false
    else if sha_stop - sha_start <> 40 then false
    else if size < 41 then false
    else if byte2int0($A.read<byte>(view, 40)) <> 32 then false
    else loop(view, pins_borrow, 0, sha_start)): bool
  val () = $A.drop<byte>(frozen, view)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in same end

(* <root>/.android-sdk-pins/<name>.zip *)
fn _zip_argument {arguments_loc:agz}{pins_loc:agz}
  {root_start:nat}{root_end:int | root_start <= root_end; root_end <= 4096}
  {name_start:nat}{name_end:int | name_start <= name_end; name_end <= 65536}
  (arguments_borrow: !$A.borrow(byte, arguments_loc, 4096), root_start: int root_start, root_end: int root_end,
   pins_borrow: !$A.borrow(byte, pins_loc, 65536), name_start: int name_start, name_end: int name_end): $P.arg_entry = let
  var out : $B.builder_v = $B.create()
  val () = _put_range(arguments_borrow, root_start, root_end, 4096, out)
  val () = _bput(out, "/.android-sdk-pins/")
  val () = _put_range(pins_borrow, name_start, name_end, 65536, out)
  val () = _bput(out, ".zip")
in _argument(out) end

(* <root>/<package-dir>/package.xml *)
fn _package_xml_argument {arguments_loc:agz}{pins_loc:agz}
  {root_start:nat}{root_end:int | root_start <= root_end; root_end <= 4096}
  {dir_start:nat}{dir_end:int | dir_start <= dir_end; dir_end <= 65536}
  (arguments_borrow: !$A.borrow(byte, arguments_loc, 4096), root_start: int root_start, root_end: int root_end,
   pins_borrow: !$A.borrow(byte, pins_loc, 65536), dir_start: int dir_start, dir_end: int dir_end): $P.arg_entry = let
  var out : $B.builder_v = $B.create()
  val () = _put_range(arguments_borrow, root_start, root_end, 4096, out)
  val () = _put(out, 47)
  val () = _put_range(pins_borrow, dir_start, dir_end, 65536, out)
  val () = _bput(out, "/package.xml")
in _argument(out) end

(* sleep seconds *)
fn _pause {seconds:nat} (seconds: int seconds): void = let
  var text : $B.builder_v = $B.create()
  val () = _put_int(text, seconds)
  val _ = _run_quiet("sleep", $L.list_vt_cons(_argument(text), $L.list_vt_nil()))
in () end

(* rm -f of the zip *)
fn _drop_zip {arguments_loc:agz}{pins_loc:agz}
  {root_start:nat}{root_end:int | root_start <= root_end; root_end <= 4096}
  {name_start:nat}{name_end:int | name_start <= name_end; name_end <= 65536}
  (arguments_borrow: !$A.borrow(byte, arguments_loc, 4096), root_start: int root_start, root_end: int root_end,
   pins_borrow: !$A.borrow(byte, pins_loc, 65536), name_start: int name_start, name_end: int name_end): void = let
  val _ = _run_quiet("rm", _arguments2(_argument_of("-f"),
    _zip_argument(arguments_borrow, root_start, root_end, pins_borrow, name_start, name_end)))
in () end

(* Downloads the zip of the line and checks its SHA-1, again (after a pause
   of pause seconds, doubled each time) while tries remain; whether the
   zip is there and is the pinned one. A zip that is not is removed. *)
fun _fetch {arguments_loc:agz}{pins_loc:agz}
  {root_start:nat}{root_end:int | root_start <= root_end; root_end <= 4096}
  {name_start:nat}{name_end:int | name_start <= name_end; name_end <= 65536}
  {url_start:nat}{url_end:int | url_start <= url_end; url_end <= 65536}
  {sha_start:nat}{sha_end:int | sha_start <= sha_end; sha_end <= 65536}
  {tries_left:nat}{pause:nat} .<tries_left>.
  (arguments_borrow: !$A.borrow(byte, arguments_loc, 4096), root_start: int root_start, root_end: int root_end,
   pins_borrow: !$A.borrow(byte, pins_loc, 65536), name_start: int name_start, name_end: int name_end,
   url_start: int url_start, url_end: int url_end, sha_start: int sha_start, sha_end: int sha_end,
   tries_left: int tries_left, pause: int pause): bool = let
  val curl_status = _run_quiet("curl", $L.list_vt_cons(_argument_of("--fail"), $L.list_vt_cons(_argument_of("--silent"),
    $L.list_vt_cons(_argument_of("--show-error"), $L.list_vt_cons(_argument_of("--location"),
    $L.list_vt_cons(_argument_of("--retry"), $L.list_vt_cons(_argument_of("3"),
    $L.list_vt_cons(_argument_of("--retry-delay"), $L.list_vt_cons(_argument_of("5"),
    $L.list_vt_cons(_argument_of("--retry-connrefused"), $L.list_vt_cons(_argument_of("--output"),
    $L.list_vt_cons(_zip_argument(arguments_borrow, root_start, root_end, pins_borrow, name_start, name_end),
    $L.list_vt_cons(_argument_token(pins_borrow, url_start, url_end), $L.list_vt_nil())))))))))))))
in
  if curl_status <> 0 then let
    val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end, ": the download failed (curl exited non-zero), nothing was installed from it\n")
    val () = _drop_zip(arguments_borrow, root_start, root_end, pins_borrow, name_start, name_end)
  in
    if tries_left <= 1 then false
    else let
      val () = _pause(pause)
    in _fetch(arguments_borrow, root_start, root_end, pins_borrow, name_start, name_end,
      url_start, url_end, sha_start, sha_end, tries_left - 1, pause * 2) end
  end
  else let
    var sum : $B.builder_v = $B.create()
    val sum_status = _run("sha1sum", $L.list_vt_cons(_zip_argument(arguments_borrow, root_start, root_end,
      pins_borrow, name_start, name_end), $L.list_vt_nil()), sum)
    val is_pinned = _sha1_is(sum, pins_borrow, sha_start, sha_end, sum_status)
  in
    if is_pinned then true
    else if sum_status <> 0 then let
      val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end, ": sha1sum could not check the download\n")
      val () = _drop_zip(arguments_borrow, root_start, root_end, pins_borrow, name_start, name_end)
    in false end
    else let
      val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end, ": the download is not the pinned one: its SHA-1 differs from the pin ")
      val () = _say_token("", pins_borrow, sha_start, sha_end, "; not installed\n")
      val () = _drop_zip(arguments_borrow, root_start, root_end, pins_borrow, name_start, name_end)
    in
      if tries_left <= 1 then false
      else let
        val () = _pause(pause)
      in _fetch(arguments_borrow, root_start, root_end, pins_borrow, name_start, name_end,
        url_start, url_end, sha_start, sha_end, tries_left - 1, pause * 2) end
    end
  end
end

(* Makes the package of the line as pinned: 0 when it is, else 1 *)
fn _install {arguments_loc:agz}{pins_loc:agz}
  {root_start:nat}{root_end:int | root_start <= root_end; root_end <= 4096}
  {name_start:nat}{name_end:int | name_start <= name_end; name_end <= 65536}
  {url_start:nat}{url_end:int | url_start <= url_end; url_end <= 65536}
  {sha_start:nat}{sha_end:int | sha_start <= sha_end; sha_end <= 65536}
  {unzip_start:nat}{unzip_end:int | unzip_start <= unzip_end; unzip_end <= 65536}
  {dir_start:nat}{dir_end:int | dir_start <= dir_end; dir_end <= 65536}{attempts:nat}{pause:nat}
  (arguments_borrow: !$A.borrow(byte, arguments_loc, 4096), root_start: int root_start, root_end: int root_end,
   pins_borrow: !$A.borrow(byte, pins_loc, 65536), name_start: int name_start, name_end: int name_end,
   url_start: int url_start, url_end: int url_end, sha_start: int sha_start, sha_end: int sha_end,
   unzip_start: int unzip_start, unzip_end: int unzip_end, dir_start: int dir_start, dir_end: int dir_end,
   attempts: int attempts, pause: int pause): int = let
  val same = _run_quiet("cmp", $L.list_vt_cons(_argument_of("-s"),
    $L.list_vt_cons(_argument_token_then(pins_borrow, name_start, name_end, ".xml"),
    $L.list_vt_cons(_package_xml_argument(arguments_borrow, root_start, root_end, pins_borrow, dir_start, dir_end),
    $L.list_vt_nil()))))
in
  if same = 0 then let
    val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end, ": already the pinned revision\n")
  in 0 end
  else let
    val made = _run_quiet("mkdir", _arguments2(_argument_of("-p"),
      _argument_root_then(arguments_borrow, root_start, root_end, "/.android-sdk-pins")))
  in
    if made <> 0 then let
      val () = _say_text("android-sdk-pins: cannot make the download directory under the SDK root\n")
    in 1 end
    else if ~_fetch(arguments_borrow, root_start, root_end, pins_borrow, name_start, name_end,
      url_start, url_end, sha_start, sha_end, attempts, pause) then let
      val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end, ": no download that matches the pinned SHA-1 could be had: refused\n")
    in 1 end
    else let
      val removed = _run_quiet("rm", _arguments3(_argument_of("-rf"), _argument_of("--"),
        _argument_root_token(arguments_borrow, root_start, root_end, pins_borrow, dir_start, dir_end)))
      val into = _run_quiet("mkdir", _arguments2(_argument_of("-p"),
        _argument_root_token(arguments_borrow, root_start, root_end, pins_borrow, unzip_start, unzip_end)))
      val unzipped = (if removed <> 0 then ~1 else if into <> 0 then ~1
        else _run_quiet("unzip", $L.list_vt_cons(_argument_of("-q"), $L.list_vt_cons(_argument_of("-o"),
          $L.list_vt_cons(_zip_argument(arguments_borrow, root_start, root_end, pins_borrow, name_start, name_end),
          $L.list_vt_cons(_argument_of("-d"),
          $L.list_vt_cons(_argument_root_token(arguments_borrow, root_start, root_end, pins_borrow, unzip_start, unzip_end),
          $L.list_vt_nil()))))))): int
      val copied = (if unzipped <> 0 then ~1
        else _run_quiet("cp", _arguments2(_argument_token_then(pins_borrow, name_start, name_end, ".xml"),
          _package_xml_argument(arguments_borrow, root_start, root_end, pins_borrow, dir_start, dir_end)))): int
      val _ = _run_quiet("rm", _arguments2(_argument_of("-f"),
        _zip_argument(arguments_borrow, root_start, root_end, pins_borrow, name_start, name_end)))
    in
      if copied = 0 then let
        val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end, ": installed, SHA-1 of the download as pinned\n")
      in 0 end
      else let
        val _ = _run_quiet("rm", _arguments3(_argument_of("-rf"), _argument_of("--"),
          _argument_root_token(arguments_borrow, root_start, root_end, pins_borrow, dir_start, dir_end)))
        val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end, ": the checked download could not be unpacked into place; the package is removed\n")
      in 1 end
    end
  end
end

(* The line [line_start, line_end) of the pins file as five words: the
   package installed as pinned (0 or 1 as _install), 2 when it is not five words *)
fn _install_line {arguments_loc:agz}{pins_loc:agz}
  {root_start:nat}{root_end:int | root_start <= root_end; root_end <= 4096}
  {line_start:nat}{line_end:nat | line_start < line_end; line_end <= 65536}{attempts:nat}{pause:nat}
  (arguments_borrow: !$A.borrow(byte, arguments_loc, 4096), root_start: int root_start, root_end: int root_end,
   pins_borrow: !$A.borrow(byte, pins_loc, 65536), line_start: int line_start, line_end: int line_end,
   attempts: int attempts, pause: int pause): int = let
  val name_end = _token_end(pins_borrow, line_start, line_end)
in
  if name_end <= line_start then 2
  else if name_end >= line_end then 2
  else let
    val url_start = name_end + 1
    val url_end = _token_end(pins_borrow, url_start, line_end)
  in
    if url_end <= url_start then 2
    else if url_end >= line_end then 2
    else let
      val sha_start = url_end + 1
      val sha_end = _token_end(pins_borrow, sha_start, line_end)
    in
      if sha_end <= sha_start then 2
      else if sha_end >= line_end then 2
      else let
        val unzip_start = sha_end + 1
        val unzip_end = _token_end(pins_borrow, unzip_start, line_end)
      in
        if unzip_end <= unzip_start then 2
        else if unzip_end >= line_end then 2
        else let
          val dir_start = unzip_end + 1
          val dir_end = _token_end(pins_borrow, dir_start, line_end)
        in
          if dir_end <= dir_start then 2
          else if dir_end <> line_end then 2
          else _install(arguments_borrow, root_start, root_end, pins_borrow, line_start, name_end,
            url_start, url_end, sha_start, sha_end, unzip_start, unzip_end, dir_start, dir_end, attempts, pause)
        end
      end
    end
  end
end

(* The lines of the pins file from start: 0 when each is installed as pinned,
   1 at the first that is not, 2 at a line that is not five words *)
fun _lines {arguments_loc:agz}{pins_loc:agz}
  {root_start:nat}{root_end:int | root_start <= root_end; root_end <= 4096}
  {start:nat}{size:nat | start <= size; size <= 65535}{attempts:nat}{pause:nat} .<size - start>.
  (arguments_borrow: !$A.borrow(byte, arguments_loc, 4096), root_start: int root_start, root_end: int root_end,
   pins_borrow: !$A.borrow(byte, pins_loc, 65536), start: int start, size: int size,
   attempts: int attempts, pause: int pause): int =
  if start >= size then 0
  else let
    val line_end = _line_end(pins_borrow, start, size)
    val status = (if line_end <= start then 0
      else if byte2int0($A.read<byte>(pins_borrow, start)) = 35 then 0
      else _install_line(arguments_borrow, root_start, root_end, pins_borrow, start, line_end, attempts, pause)): int
  in
    if status <> 0 then status
    else if line_end >= size then 0
    else _lines(arguments_borrow, root_start, root_end, pins_borrow, line_end + 1, size, attempts, pause)
  end

(* ============================================================
   The command
   ============================================================ *)

(* Whether the arguments are "<program> key" *)
fn _is_key {l:agz}{size:nat | size <= 4096}
  (arguments_borrow: !$A.borrow(byte, l, 4096), size: int size): bool = let
  val program_end = _argument_end(arguments_borrow, 0, size)
in
  if program_end >= size then false
  else let
    val command_start = program_end + 1
    val command_end = _argument_end(arguments_borrow, command_start, size)
  in _is(arguments_borrow, command_start, command_end, "key", 4096) end
end

(* The digest sha256sum prints for pins.txt, 64 hex digits and a newline, on
   stdout (android.yml's cache key ends with it): 0, or 2 when it cannot be had *)
fn _key (): int = let
  var sum : $B.builder_v = $B.create()
  val status = _run("sha256sum", $L.list_vt_cons(_argument_of("pins.txt"), $L.list_vt_nil()), sum)
  val @(array, size) = $B.to_arr(sum)
  val @(frozen, view) = $A.freeze<byte>(array)
  fun loop {l:agz}{i:nat | i <= 64} .<64 - i>.
    (view: !$A.borrow(byte, l, 524288), i: int i): void =
    if i >= 64 then print_char('\n')
    else let
      val () = print_char(int2char0(byte2int0($A.read<byte>(view, i))))
    in loop(view, i + 1) end
  val code = (if status <> 0 then 2
    else if size < 65 then 2
    else if byte2int0($A.read<byte>(view, 64)) <> 32 then 2
    else let val () = loop(view, 0) in 0 end): int
  val () = $A.drop<byte>(frozen, view)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
  val () = (if code <> 0 then _say_text("android-sdk-pins: sha256sum could not digest pins.txt\n") else ())
in code end

fn _status (code: int): void =
  if code <> 0 then exit_void(code) else ()

implement main0 () = let
  val arguments = $A.alloc<byte>(4096)
  val arguments_size = _arguments_read(arguments)
  val @(frozen_arguments, arguments_borrow) = $A.freeze<byte>(arguments)
  val @(root_start, root_end) = _root_range(arguments_borrow, arguments_size)
  val usable = (arguments_size < 4095 && root_end > root_start): bool
  val status = (if arguments_size < 4095 && _is_key(arguments_borrow, arguments_size) then _key()
    else if ~usable then let
      val () = _say_text("usage: android-sdk-pins install <sdk-root> | key   (in the directory with pins.txt)\n")
    in 2 end
    else let
      val pins = $A.alloc<byte>(65536)
      val pins_size = _read_pins(pins)
      val @(frozen_pins, pins_borrow) = $A.freeze<byte>(pins)
      val code = (if pins_size < 0 then let
          val () = (if pins_size = ~2 then _say_text("android-sdk-pins: pins.txt is larger than 65535 bytes\n")
            else _say_text("android-sdk-pins: cannot read pins.txt in the current directory\n"))
        in 2 end
        else _lines(arguments_borrow, root_start, root_end, pins_borrow, 0, pins_size,
          _number_env("ANDROID_SDK_PINS_ATTEMPTS", 3, 1, 10),
          _number_env("ANDROID_SDK_PINS_PAUSE_S", 15, 0, 3600))): int
      val () = $A.drop<byte>(frozen_pins, pins_borrow)
      val () = $A.free<byte>($A.thaw<byte>(frozen_pins))
    in code end): int
  val () = $A.drop<byte>(frozen_arguments, arguments_borrow)
  val () = $A.free<byte>($A.thaw<byte>(frozen_arguments))
in _status(status) end
