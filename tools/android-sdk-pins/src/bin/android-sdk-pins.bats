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
   repin: reading text (android-smoke, pins that move)
   ============================================================ *)

fn _length {text_size:nat} (text: string text_size): int text_size = g1u2i(string1_length(text))

(* Whether the bytes at `at` are the literal, all within the first `size` bytes *)
fn _literal_at {l:agz}{cap:pos}{size:nat | size <= cap}{at:nat}{literal_size:nat}
  (bytes: !$A.borrow(byte, l, cap), size: int size, at: int at,
    literal: string literal_size): bool = let
  fun loop {literal_size:nat}{j:nat | j <= literal_size} .<literal_size - j>.
    (bytes: !$A.borrow(byte, l, cap), size: int size, at: int at,
     literal: string literal_size, literal_length: int literal_size, j: int j): bool =
    if j >= literal_length then true
    else if at + j >= size then false
    else if byte2int0($A.read<byte>(bytes, at + j)) <> char2int0(string_get_at(literal,
      j)) then false
    else loop(bytes, size, at, literal, literal_length, j + 1)
in loop(bytes, size, at, literal, _length(literal), 0) end

(* The first place at or after start where the literal is, else size *)
fun _find {l:agz}{cap:pos}{size:nat | size <= cap}{start:nat | start <= size}{literal_size:nat}
  .<size - start>.
  (bytes: !$A.borrow(byte, l, cap), size: int size, start: int start, literal: string literal_size)
  : [found:nat | start <= found; found <= size] int found =
  if start >= size then start
  else if _literal_at(bytes, size, start, literal) then start
  else _find(bytes, size, start + 1, literal)

(* The first place at or after start where the byte is, else size *)
fun _find_byte {l:agz}{cap:pos}{size:nat | size <= cap}{start:nat | start <= size} .<size - start>.
  (bytes: !$A.borrow(byte, l, cap), size: int size, start: int start, value: int)
  : [found:nat | start <= found; found <= size] int found =
  if start >= size then start
  else if byte2int0($A.read<byte>(bytes, start)) = value then start
  else _find_byte(bytes, size, start + 1, value)

(* position + length, or size when that is past it *)
fn _after {position:nat}{size:nat | position <= size}{length:nat}
  (position: int position, length: int length, size: int size)
  : [stop:nat | position <= stop; stop <= size] int stop =
  if position + length <= size then position + length else size

(* The first place in [start, limit) where the whole literal is, else limit *)
fn _find_within {l:agz}{cap:pos}{size:nat | size <= cap}{start:nat}
  {limit:nat | start <= limit; limit <= size}
  {literal_size:nat}
  (bytes: !$A.borrow(byte, l, cap), size: int size, start: int start, limit: int limit,
   literal: string literal_size): [found:nat | start <= found; found <= limit] int found = let
  val found = _find(bytes, size, start, literal)
in
  if found < limit then (if found + _length(literal) <= limit then found else limit) else limit
end

(* The text between the first `opening` and the next `closing` in [start, limit),
   as [text_start, text_stop); (0, 0) when either is missing *)
fn _text_range {l:agz}{cap:pos}{size:nat | size <= cap}{start:nat}
  {limit:nat | start <= limit; limit <= size}
  {opening_size:nat}{closing_size:nat}
  (bytes: !$A.borrow(byte, l, cap), size: int size, start: int start, limit: int limit,
   opening: string opening_size, closing: string closing_size)
  : [text_start,text_stop:nat | text_start <= text_stop; text_stop <= limit] @(int text_start,
    int text_stop) = let
  val opening_at = _find_within(bytes, size, start, limit, opening)
in
  if opening_at >= limit then @(0, 0)
  else let
    val text_start = _after(opening_at, _length(opening), limit)
    val text_stop = _find_within(bytes, size, text_start, limit, closing)
  in
    if text_stop >= limit then @(0, 0) else @(text_start, text_stop)
  end
end

(* The decimal number that starts at start, with the place after it; ~1 when
   there is no digit. A number past 100000000 stops growing. *)
fun _digits {l:agz}{cap:pos}{size:nat | size <= cap}{start:nat | start <= size}{value:nat}
  .<size - start>.
  (bytes: !$A.borrow(byte, l, cap), size: int size, start: int start, value: int value)
  : [result:nat][stop:nat | start <= stop; stop <= size] @(int result, int stop) =
  if start >= size then @(value, start)
  else let
    val digit = _digit_of(byte2int0($A.read<byte>(bytes, start)))
  in
    if digit < 0 then @(value, start)
    else if value > 100000000 then _digits(bytes, size, start + 1, value)
    else _digits(bytes, size, start + 1, value * 10 + digit)
  end

fn _number_at {l:agz}{cap:pos}{size:nat | size <= cap}{start:nat | start <= size}
  (bytes: !$A.borrow(byte, l, cap), size: int size, start: int start)
  : [value:int | ~1 <= value][stop:nat | start <= stop; stop <= size] @(int value, int stop) = let
  val @(value, stop) = _digits(bytes, size, start, 0)
in
  if stop <= start then @(~1, stop) else @(value, stop)
end

(* The number inside <opening>..<closing> in [start, limit); ~1 when it is not there *)
fn _element_number {l:agz}{cap:pos}{size:nat | size <= cap}{start:nat}
  {limit:nat | start <= limit; limit <= size}
  {opening_size:nat}{closing_size:nat}
  (bytes: !$A.borrow(byte, l, cap), size: int size, start: int start, limit: int limit,
   opening: string opening_size,
     closing: string closing_size): [value:int | ~1 <= value] int value = let
  val @(text_start, text_stop) = _text_range(bytes, size, start, limit, opening, closing)
in
  if text_stop <= text_start then ~1
  else let val @(value, _) = _number_at(bytes, size, text_start) in value end
end

(* The revision in [start, limit): major, minor and micro, each ~1 when absent *)
fn _revision {l:agz}{cap:pos}{size:nat | size <= cap}{start:nat}
  {limit:nat | start <= limit; limit <= size}
  (bytes: !$A.borrow(byte, l, cap), size: int size, start: int start, limit: int limit)
  : [major,minor,micro:int | ~1 <= major; ~1 <= minor; ~1 <= micro] @(int major, int minor,
    int micro) = let
  val @(inner_start, inner_stop) = _text_range(bytes, size, start, limit, "<revision>",
    "</revision>")
  val major = _element_number(bytes, size, inner_start, inner_stop, "<major>", "</major>")
  val minor = _element_number(bytes, size, inner_start, inner_stop, "<minor>", "</minor>")
  val micro = _element_number(bytes, size, inner_start, inner_stop, "<micro>", "</micro>")
in @(major, minor, micro) end

fn _component (value: int): int = if value < 0 then 0 else value

(* Whether the first revision is later than the second; an absent minor or micro is 0 *)
fn _later (first_major: int, first_minor: int, first_micro: int,
           second_major: int, second_minor: int, second_micro: int): bool =
  if _component(first_major) > _component(second_major) then true
  else if _component(first_major) < _component(second_major) then false
  else if _component(first_minor) > _component(second_minor) then true
  else if _component(first_minor) < _component(second_minor) then false
  else _component(first_micro) > _component(second_micro)

fun _same_loop {l1:agz}{l2:agz}{cap1,cap2:pos}{start1,start2:nat}
  {count:nat | start1 + count <= cap1; start2 + count <= cap2}{i:nat | i <= count} .<count - i>.
  (bytes1: !$A.borrow(byte, l1, cap1), start1: int start1, bytes2: !$A.borrow(byte, l2, cap2),
   start2: int start2, count: int count, i: int i): bool =
  if i >= count then true
  else if byte2int0($A.read<byte>(bytes1, start1 + i)) <> byte2int0($A.read<byte>(bytes2,
    start2 + i)) then false
  else _same_loop(bytes1, start1, bytes2, start2, count, i + 1)

(* Whether bytes1[start1, stop1) and bytes2[start2, stop2) are the same text *)
fn _same_text {l1:agz}{l2:agz}{cap1,cap2:pos}
  {start1:nat}{stop1:int | start1 <= stop1; stop1 <= cap1}
  {start2:nat}{stop2:int | start2 <= stop2; stop2 <= cap2}
  (bytes1: !$A.borrow(byte, l1, cap1), start1: int start1, stop1: int stop1,
   bytes2: !$A.borrow(byte, l2, cap2), start2: int start2, stop2: int stop2): bool = let
  val count1 = stop1 - start1
  val count2 = stop2 - start2
in
  if count1 = count2 then _same_loop(bytes1, start1, bytes2, start2, count1, 0) else false
end

fun _same_loop_in {l:agz}{cap:pos}{start1,start2:nat}
  {count:nat | start1 + count <= cap; start2 + count <= cap}{i:nat | i <= count} .<count - i>.
  (bytes: !$A.borrow(byte, l, cap), start1: int start1, start2: int start2, count: int count,
    i: int i): bool =
  if i >= count then true
  else if byte2int0($A.read<byte>(bytes, start1 + i)) <> byte2int0($A.read<byte>(bytes,
    start2 + i)) then false
  else _same_loop_in(bytes, start1, start2, count, i + 1)

(* Whether bytes[start1, stop1) and bytes[start2, stop2) are the same text *)
fn _same_text_in {l:agz}{cap:pos}{start1:nat}{stop1:int | start1 <= stop1; stop1 <= cap}
  {start2:nat}{stop2:int | start2 <= stop2; stop2 <= cap}
  (bytes: !$A.borrow(byte, l, cap), start1: int start1, stop1: int stop1,
   start2: int start2, stop2: int stop2): bool = let
  val count1 = stop1 - start1
  val count2 = stop2 - start2
in
  if count1 = count2 then _same_loop_in(bytes, start1, start2, count1, 0) else false
end

(* The place after the last slash of [start, stop), start when there is none *)
fun _after_last_slash {l:agz}{cap:pos}{start:nat}{stop:nat | start <= stop; stop <= cap}
  .<stop - start>.
  (bytes: !$A.borrow(byte, l, cap), start: int start, stop: int stop)
  : [place:nat | start <= place; place <= stop] int place =
  if stop <= start then start
  else if byte2int0($A.read<byte>(bytes, stop - 1)) = 47 then stop
  else _after_last_slash(bytes, start, stop - 1)

fn _class_ok (value: int, kind: int): bool =
  if kind = 0 then ((value >= 48 && value <= 57) || (value >= 97 && value <= 102))
  else ((value >= 48 && value <= 57) || (value >= 65 && value <= 90) || (value >= 97
    && value <= 122)
        || value = 46 || value = 45 || value = 95)

(* Whether every byte of [start, stop) is lower case hex (kind 0) or a letter, digit,
   dot, minus or underscore (kind 1) *)
fun _all_class {l:agz}{cap:pos}{start:nat}{stop:int | start <= stop; stop <= cap} .<stop - start>.
  (bytes: !$A.borrow(byte, l, cap), start: int start, stop: int stop, kind: int): bool =
  if start >= stop then true
  else if ~_class_ok(byte2int0($A.read<byte>(bytes, start)), kind) then false
  else _all_class(bytes, start + 1, stop, kind)

(* ============================================================
   repin: files
   ============================================================ *)

(* The file at path into buffer: its size, at most size - 1 bytes; ~1 when it
   cannot be read and ~2 when it is larger. The path is consumed. *)
fn _read_file {l:agz}{size:pos}
  (path: $B.builder_v, buffer: !$A.arr(byte, l, size), size: int size)
  : [count:int | ~2 <= count; count <= size - 1] int count = let
  val () = _put(path, 0)
  val @(path_array, _) = $B.to_arr(path)
  val @(frozen_path, path_borrow) = $A.freeze<byte>(path_array)
  val result = (case+ $F.file_open(path_borrow, 524288, $F.ReadOnly(), $F.OpenExisting(), 0) of
    | ~$R.err(_) => ~1
    | ~$R.ok(fd) => let
        val file_size = (case+ $F.fd_size(fd) of
          | ~$R.ok(size) => size
          | ~$R.err(_) => ~1): [file_size:int | ~1 <= file_size] int file_size
        val count = (if file_size < 0 then ~1
          else if file_size >= size then ~2
          else (case+ $F.file_read(fd, buffer, size) of
            | ~$R.ok(count) => (if count = file_size then count else ~1)
            | ~$R.err(_) => ~1)): [count:int | ~2 <= count; count <= size - 1] int count
        val () = $R.discard<int><$F.io_error>($F.file_close(fd))
      in count end): [count:int | ~2 <= count; count <= size - 1] int count
  val () = $A.drop<byte>(frozen_path, path_borrow)
  val () = $A.free<byte>($A.thaw<byte>(frozen_path))
in result end

(* The content as the file at path, created or emptied first; whether it was written
   and closed. Both are consumed. *)
fn _write_file (path: $B.builder_v, content: $B.builder_v): bool = let
  val () = _put(path, 0)
  val @(path_array, _) = $B.to_arr(path)
  val @(frozen_path, path_borrow) = $A.freeze<byte>(path_array)
  val written = (case+ $F.file_open(path_borrow, 524288, $F.WriteOnly(), $F.CreateOrTruncate(),
    420) of
    | ~$R.err(_) => let val () = $B.builder_free(content) in false end
    | ~$R.ok(fd) => let
        val @(array, size) = $B.to_arr(content)
        val @(frozen, view) = $A.freeze<byte>(array)
        val @(left, right) = $A.borrow_split<byte>(frozen, view, size)
        val wrote = (if size <= 0 then true
          else (case+ $F.file_write(fd, left,
            size) of | ~$R.ok(_) => true | ~$R.err(_) => false)): bool
        val closed = (case+ $F.file_close(fd) of | ~$R.ok(_) => true | ~$R.err(_) => false): bool
        val whole = $A.borrow_join<byte>(frozen, left, right)
        val () = $A.drop<byte>(frozen, whole)
        val () = $A.free<byte>($A.thaw<byte>(frozen))
      in wrote && closed end): bool
  val () = $A.drop<byte>(frozen_path, path_borrow)
  val () = $A.free<byte>($A.thaw<byte>(frozen_path))
in written end

(* stdout gets the builder's bytes; the builder is consumed *)
fn _print_builder (text: $B.builder_v): void = let
  val @(array, size) = $B.to_arr(text)
  val @(frozen, view) = $A.freeze<byte>(array)
  fun loop {l:agz}{i:nat}{size:nat | i <= size; size <= 524288} .<size - i>.
    (view: !$A.borrow(byte, l, 524288), i: int i, size: int size): void =
    if i >= size then ()
    else let
      val () = print_char(int2char0(byte2int0($A.read<byte>(view, i))))
    in loop(view, i + 1, size) end
  val () = loop(view, 0, size)
  val () = $A.drop<byte>(frozen, view)
in $A.free<byte>($A.thaw<byte>(frozen)) end

(* The feed directory (the arguments' bytes [dir_start, dir_stop)), a slash and
   a file name made of a literal *)
fn _feed_path {arguments_loc:agz}{dir_start:nat}
  {dir_stop:int | dir_start <= dir_stop; dir_stop <= 4096}
  {name_size:nat}
  (arguments_borrow: !$A.borrow(byte, arguments_loc, 4096), dir_start: int dir_start,
   dir_stop: int dir_stop, name: string name_size): $B.builder_v = let
  var path : $B.builder_v = $B.create()
  val () = _put_range(arguments_borrow, dir_start, dir_stop, 4096, path)
  val () = _put(path, 47)
  val () = _bput(path, name)
in path end

(* The same for the file <archive>.age, the archive being bytes[start, stop) *)
fn _age_path {arguments_loc:agz}{dir_start:nat}
  {dir_stop:int | dir_start <= dir_stop; dir_stop <= 4096}
  {l:agz}{cap:pos}{start:nat}{stop:int | start <= stop; stop <= cap}
  (arguments_borrow: !$A.borrow(byte, arguments_loc, 4096), dir_start: int dir_start,
   dir_stop: int dir_stop, bytes: !$A.borrow(byte, l, cap), start: int start, stop: int stop,
     cap: int cap)
  : $B.builder_v = let
  var path : $B.builder_v = $B.create()
  val () = _put_range(arguments_borrow, dir_start, dir_stop, 4096, path)
  val () = _put(path, 47)
  val () = _put_range(bytes, start, stop, cap, path)
  val () = _bput(path, ".age")
in path end

(* The whole days the file at path holds as digits and a newline, else ~1 *)
fn _read_age (path: $B.builder_v): [age:int | ~1 <= age] int age = let
  val buffer = $A.alloc<byte>(64)
  val count = _read_file(path, buffer, 64)
  val @(frozen, view) = $A.freeze<byte>(buffer)
  val age = (if count <= 0 then ~1
    else let
      val @(value, stop) = _number_at(view, count, 0)
    in
      if value < 0 then ~1
      else if stop >= count then value
      else if stop + 1 = count && byte2int0($A.read<byte>(view, stop)) = 10 then value
      else ~1
    end): [age:int | ~1 <= age] int age
  val () = $A.drop<byte>(frozen, view)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in age end

(* ============================================================
   repin: the newest stable revision of a package in a feed
   ============================================================ *)

(* The id of the channel that is called stable, as [start, stop) of the feed;
   (0, 0) when there is none *)
fun _stable_channel {l:agz}{cap:pos}{size:nat | size <= cap}{start:nat | start <= size}
  .<size - start>.
  (bytes: !$A.borrow(byte, l, cap), size: int size, start: int start)
  : [id_start,id_stop:nat | id_start <= id_stop; id_stop <= size] @(int id_start, int id_stop) = let
  val channel_at = _find(bytes, size, start, "<channel id=\"")
in
  if channel_at >= size then @(0, 0)
  else let
    val id_start = _after(channel_at, _length("<channel id=\""), size)
    val id_stop = _find_byte(bytes, size, id_start, 34)
  in
    if _literal_at(bytes, size, id_stop, "\">stable</channel>") then @(id_start, id_stop)
    else _stable_channel(bytes, size, channel_at + 1)
  end
end

(* Whether the block [block_start, block_stop) is on the channel with the id
   [id_start, id_stop) *)
fn _on_channel {l:agz}{cap:pos}{size:nat | size <= cap}{block_start:nat}
  {block_stop:nat | block_start <= block_stop; block_stop <= size}
  {id_start:nat}{id_stop:int | id_start <= id_stop; id_stop <= size}
  (bytes: !$A.borrow(byte, l, cap), size: int size, block_start: int block_start,
    block_stop: int block_stop,
   id_start: int id_start, id_stop: int id_stop): bool = let
  val reference_at = _find_within(bytes, size, block_start, block_stop, "<channelRef ref=\"")
in
  if id_stop <= id_start then false
  else if reference_at >= block_stop then false
  else let
    val reference_start = _after(reference_at, _length("<channelRef ref=\""), size)
    val reference_stop = _find_byte(bytes, size, reference_start, 34)
  in _same_text_in(bytes, reference_start, reference_stop, id_start, id_stop) end
end

(* Of the blocks <remotePackage path="..."> of the feed at or after start that are
   the package of the other buffer's path [path_start, path_stop) (not obsolete),
   on the stable channel [id_start, id_stop), with the extension level
   [level_start, level_stop) of the other buffer when both name one: the block of the
   latest revision. The answer is (whether there is one, its start, its stop). *)
fun _best_block {feed_loc:agz}{local_loc:agz}{feed_cap:pos}{local_cap:pos}
  {feed_size:nat | feed_size <= feed_cap}
  {path_start:nat}{path_stop:int | path_start <= path_stop; path_stop <= local_cap}
  {id_start:nat}{id_stop:int | id_start <= id_stop; id_stop <= feed_size}
  {level_start:nat}{level_stop:int | level_start <= level_stop; level_stop <= local_cap}
  {start:nat | start <= feed_size}{best_start:nat}
    {best_stop:int | best_start <= best_stop; best_stop <= feed_size}
  .<feed_size - start>.
  (feed: !$A.borrow(byte, feed_loc, feed_cap), feed_size: int feed_size,
   package_xml: !$A.borrow(byte, local_loc, local_cap), path_start: int path_start,
     path_stop: int path_stop,
   id_start: int id_start, id_stop: int id_stop, level_start: int level_start,
     level_stop: int level_stop,
   start: int start, has_best: bool, best_start: int best_start, best_stop: int best_stop)
  : [block_start,block_stop:nat | block_start <= block_stop; block_stop <= feed_size]
    @(bool, int block_start, int block_stop) = let
  val block_opening = "<remotePackage path=\""
  val block_at = _find(feed, feed_size, start, block_opening)
in
  if block_at >= feed_size then @(has_best, best_start, best_stop)
  else let
    val package_start = _after(block_at, _length(block_opening), feed_size)
    val package_stop = _find_byte(feed, feed_size, package_start, 34)
    val block_stop = _find(feed, feed_size, package_stop, "</remotePackage>")
    val is_package = (_same_text(feed, package_start, package_stop, package_xml, path_start,
      path_stop)
      && _literal_at(feed, feed_size, package_stop, "\">")): bool
    val level_ok = (if level_stop <= level_start then true
      else let
        val @(block_level_start, block_level_stop) =
          _text_range(feed, feed_size, block_at, block_stop, "<extension-level>",
            "</extension-level>")
      in
        if block_level_stop <= block_level_start then true
        else _same_text(feed, block_level_start, block_level_stop, package_xml, level_start,
          level_stop)
      end): bool
    val usable = (is_package && level_ok
      && _on_channel(feed, feed_size, block_at, block_stop, id_start, id_stop)): bool
    val better = (if ~usable then false
      else if ~has_best then true
      else let
        val @(major, minor, micro) = _revision(feed, feed_size, block_at, block_stop)
        val @(best_major, best_minor, best_micro) = _revision(feed, feed_size, best_start,
          best_stop)
      in _later(major, minor, micro, best_major, best_minor, best_micro) end): bool
  in
    if better then _best_block(feed, feed_size, package_xml, path_start, path_stop, id_start,
      id_stop,
      level_start, level_stop, block_at + 1, true, block_at, block_stop)
    else _best_block(feed, feed_size, package_xml, path_start, path_stop, id_start, id_stop,
      level_start, level_stop, block_at + 1, has_best, best_start, best_stop)
  end
end

(* The first <archive> of [start, stop) that is for Linux on x86_64: host-os linux
   or none, host-bits 64 or none, no host-arch. (whether there is one, its start, its stop) *)
fun _linux_archive {l:agz}{cap:pos}{size:nat | size <= cap}{start:nat}
  {stop:nat | start <= stop; stop <= size}
  .<stop - start>.
  (bytes: !$A.borrow(byte, l, cap), size: int size, start: int start, stop: int stop)
  : [archive_start,archive_stop:nat | archive_start <= archive_stop; archive_stop <= stop]
    @(bool, int archive_start, int archive_stop) = let
  val archive_at = _find_within(bytes, size, start, stop, "<archive>")
in
  if archive_at >= stop then @(false, 0, 0)
  else let
    val archive_stop = _find_within(bytes, size, archive_at, stop, "</archive>")
    val @(os_start, os_stop) = _text_range(bytes, size, archive_at, archive_stop, "<host-os>",
      "</host-os>")
    val @(bits_start, bits_stop) = _text_range(bytes, size, archive_at, archive_stop,
      "<host-bits>", "</host-bits>")
    val arch_at = _find_within(bytes, size, archive_at, archive_stop, "<host-arch>")
    val os_ok = (if os_stop <= os_start then true
      else os_stop - os_start = 5 && _literal_at(bytes, size, os_start, "linux")): bool
    val bits_ok = (if bits_stop <= bits_start then true
      else bits_stop - bits_start = 2 && _literal_at(bytes, size, bits_start, "64")): bool
  in
    if os_ok && bits_ok && arch_at >= archive_stop then @(true, archive_at, archive_stop)
    else _linux_archive(bytes, size, archive_at + 1, stop)
  end
end

(* The revision as a record writes it: major, then .minor and .micro when present *)
fn _put_revision {major,minor,micro:int | ~1 <= major; ~1 <= minor; ~1 <= micro}
  (out: !$B.builder_v >> $B.builder_v, major: int major, minor: int minor,
    micro: int micro): void = let
  val () = (if major < 0 then _put(out, 48) else _put_int(out, major))
  val () = (if minor < 0 then () else let val () = _put(out, 46) in _put_int(out, minor) end)
in if micro < 0 then () else let val () = _put(out, 46) in _put_int(out, micro) end end

(* ============================================================
   repin: one pin
   ============================================================ *)

(* The pins file's bytes [start, stop) followed by a literal, as a path *)
fn _name_path {pins_loc:agz}{start:nat}{stop:int | start <= stop; stop <= 65536}{suffix_size:nat}
  (pins_borrow: !$A.borrow(byte, pins_loc, 65536), start: int start, stop: int stop,
   suffix: string suffix_size): $B.builder_v = let
  var path : $B.builder_v = $B.create()
  val () = _put_range(pins_borrow, start, stop, 65536, path)
  val () = _bput(path, suffix)
in path end

(* A record line of the relock's table (kind, name, old, new, age in days, status,
   separated by tabs) on stdout. The status word is "moved" or "current". *)
fn _print_record {pins_loc:agz}{name_start:nat}
  {name_end:int | name_start <= name_end; name_end <= 65536}
  {old_major,old_minor,old_micro:int | ~1 <= old_major; ~1 <= old_minor; ~1 <= old_micro}
  {new_major,new_minor,new_micro:int | ~1 <= new_major; ~1 <= new_minor; ~1 <= new_micro}
  {age:nat}{status_size:nat}
  (pins_borrow: !$A.borrow(byte, pins_loc, 65536), name_start: int name_start,
    name_end: int name_end,
   old_major: int old_major, old_minor: int old_minor, old_micro: int old_micro,
   new_major: int new_major, new_minor: int new_minor, new_micro: int new_micro,
   age: int age, status: string status_size): void = let
  var record : $B.builder_v = $B.create()
  val () = _bput(record, "android-sdk\t")
  val () = _put_range(pins_borrow, name_start, name_end, 65536, record)
  val () = _put(record, 9)
  val () = _put_revision(record, old_major, old_minor, old_micro)
  val () = _put(record, 9)
  val () = _put_revision(record, new_major, new_minor, new_micro)
  val () = _put(record, 9)
  val () = _put_int(record, age)
  val () = _put(record, 9)
  val () = _bput(record, status)
  val () = _put(record, 10)
in _print_builder(record) end

(* Examines the package of one pins line in one feed: 0 when the pin is the newest
   stable revision (its record is printed), 1 when a newer one is pinned (the new
   line is appended to out, the new package.xml written, the record printed), 3
   when the feed has no stable revision of the package, 2 when the package cannot
   be examined (said on stderr) *)
fn _in_feed {arguments_loc:agz}{pins_loc:agz}{xml_loc:agz}{feed_loc:agz}
  {dir_start:nat}{dir_stop:int | dir_start <= dir_stop; dir_stop <= 4096}
  {name_start:nat}{name_end:int | name_start <= name_end; name_end <= 65536}
  {url_start:nat}{url_end:int | url_start <= url_end; url_end <= 65536}
  {sha_start:nat}{sha_end:int | sha_start <= sha_end; sha_end <= 65536}
  {line_end:nat | sha_end <= line_end; line_end <= 65536}
  {xml_size:nat | xml_size <= 65536}{feed_size:nat | feed_size <= 1048576}
  (arguments_borrow: !$A.borrow(byte, arguments_loc, 4096), dir_start: int dir_start,
    dir_stop: int dir_stop,
   pins_borrow: !$A.borrow(byte, pins_loc, 65536), name_start: int name_start,
     name_end: int name_end,
   url_start: int url_start, url_end: int url_end, sha_start: int sha_start, sha_end: int sha_end,
   line_end: int line_end,
   xml: !$A.borrow(byte, xml_loc, 65536), xml_size: int xml_size,
   feed: !$A.borrow(byte, feed_loc, 1048576), feed_size: int feed_size,
   out: !$B.builder_v >> $B.builder_v): int = let
  val package_at = _find(xml, xml_size, 0, "<localPackage path=\"")
in
  if package_at >= xml_size then let
    val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end,
      ".xml has no <localPackage path=\"..\">\n")
  in 2 end
  else let
    val package_start = _after(package_at, _length("<localPackage path=\""), xml_size)
    val package_stop = _find_byte(xml, xml_size, package_start, 34)
    val @(old_major, old_minor, old_micro) = _revision(xml, xml_size, package_at, xml_size)
    val @(level_start, level_stop) =
      _text_range(xml, xml_size, package_at, xml_size, "<extension-level>", "</extension-level>")
    val @(id_start, id_stop) = _stable_channel(feed, feed_size, 0)
  in
    if old_major < 0 then let
      val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end,
        ".xml has no <revision> with a <major>\n")
    in 2 end
    else if id_stop <= id_start then 3
    else let
      val @(has_best, best_start, best_stop) = _best_block(feed, feed_size, xml, package_start,
        package_stop,
        id_start, id_stop, level_start, level_stop, 0, false, 0, 0)
    in
      if ~has_best then 3
      else let
        val @(new_major, new_minor, new_micro) = _revision(feed, feed_size, best_start, best_stop)
      in
        if ~_later(new_major, new_minor, new_micro, old_major, old_minor, old_micro) then let
          val archive_start = _after_last_slash(pins_borrow, url_start, url_end)
          val age = _read_age(_age_path(arguments_borrow, dir_start, dir_stop, pins_borrow,
            archive_start, url_end, 65536))
        in
          if age < 0 then let
            val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end,
              ": the age file of the pinned archive cannot be read\n")
          in 2 end
          else let
            val () = _print_record(pins_borrow, name_start, name_end, old_major, old_minor,
              old_micro,
              old_major, old_minor, old_micro, age, "current")
          in 0 end
        end
        else let
          val @(has_archive, archive_start, archive_stop) = _linux_archive(feed, feed_size,
            best_start, best_stop)
          val @(sum_start, sum_stop) =
            _text_range(feed, feed_size, archive_start, archive_stop, "<checksum>", "</checksum>")
          val @(file_start, file_stop) =
            _text_range(feed, feed_size, archive_start, archive_stop, "<url>", "</url>")
          val @(display_start, display_stop) =
            _text_range(feed, feed_size, best_start, best_stop, "<display-name>", "</display-name>")
          val @(revision_start, revision_stop) =
            _text_range(xml, xml_size, package_at, xml_size, "<revision>", "</revision>")
          val @(old_display_start, old_display_stop) =
            _text_range(xml, xml_size, package_at, xml_size, "<display-name>", "</display-name>")
        in
          if ~has_archive then let
            val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end,
              ": the newest stable revision has no archive for Linux on x86_64 in the feed\n")
          in 2 end
          else if sum_stop - sum_start <> 40 then let
            val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end,
              ": the feed's checksum is not 40 characters\n")
          in 2 end
          else if ~_all_class(feed, sum_start, sum_stop, 0) then let
            val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end,
              ": the feed's checksum is not lower case hex\n")
          in 2 end
          else if file_stop <= file_start then let
            val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end,
              ": the feed's archive has no url\n")
          in 2 end
          else if ~_all_class(feed, file_start, file_stop, 1) then let
            val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end,
              ": the feed's archive name has a character that is not a letter, digit, . - _\n")
          in 2 end
          else if display_stop <= display_start then let
            val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end,
              ": the feed's package has no display name\n")
          in 2 end
          else if revision_stop <= revision_start then let
            val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end,
              ".xml has no revision to replace\n")
          in 2 end
          else if old_display_stop <= old_display_start then let
            val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end,
              ".xml has no display name to replace\n")
          in 2 end
          else if old_display_start < revision_stop then let
            val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end,
              ".xml has its display name before its revision\n")
          in 2 end
          else let
            val age = _read_age(_age_path(arguments_borrow, dir_start, dir_stop, feed,
              file_start, file_stop, 1048576))
          in
            if age < 0 then let
              val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end,
                ": the age file of the new archive cannot be read\n")
            in 2 end
            else let
              var xml_out : $B.builder_v = $B.create()
              val () = _put_range(xml, 0, revision_start, 65536, xml_out)
              val () = _bput(xml_out, "<major>")
              val () = (if new_major < 0 then _put(xml_out, 48) else _put_int(xml_out, new_major))
              val () = _bput(xml_out, "</major>")
              val () = (if new_minor < 0 then ()
                else let
                  val () = _bput(xml_out, "<minor>")
                  val () = _put_int(xml_out, new_minor)
                in _bput(xml_out, "</minor>") end)
              val () = (if new_micro < 0 then ()
                else let
                  val () = _bput(xml_out, "<micro>")
                  val () = _put_int(xml_out, new_micro)
                in _bput(xml_out, "</micro>") end)
              val () = _put_range(xml, revision_stop, old_display_start, 65536, xml_out)
              val () = _put_range(feed, display_start, display_stop, 1048576, xml_out)
              val () = _put_range(xml, old_display_stop, xml_size, 65536, xml_out)
              val xml_path = _name_path(pins_borrow, name_start, name_end, ".xml")
            in
              if ~_write_file(xml_path, xml_out) then let
                val () = _say_token("android-sdk-pins: ", pins_borrow, name_start, name_end,
                  ": the new package.xml cannot be written\n")
              in 2 end
              else let
                val prefix_end = _after_last_slash(pins_borrow, url_start, url_end)
                val () = _put_range(pins_borrow, name_start, name_end, 65536, out)
                val () = _put(out, 32)
                val () = _put_range(pins_borrow, url_start, prefix_end, 65536, out)
                val () = _put_range(feed, file_start, file_stop, 1048576, out)
                val () = _put(out, 32)
                val () = _put_range(feed, sum_start, sum_stop, 1048576, out)
                val () = _put_range(pins_borrow, sha_end, line_end, 65536, out)
                val () = _print_record(pins_borrow, name_start, name_end, old_major, old_minor,
                  old_micro,
                  new_major, new_minor, new_micro, age, "moved")
              in 1 end
            end
          end
        end
      end
    end
  end
end

(* _in_feed with the builder handed in and handed back, so that the branches of the
   callers end in the same type *)
fn _in_feed_owned {arguments_loc:agz}{pins_loc:agz}{xml_loc:agz}{feed_loc:agz}
  {dir_start:nat}{dir_stop:int | dir_start <= dir_stop; dir_stop <= 4096}
  {name_start:nat}{name_end:int | name_start <= name_end; name_end <= 65536}
  {url_start:nat}{url_end:int | url_start <= url_end; url_end <= 65536}
  {sha_start:nat}{sha_end:int | sha_start <= sha_end; sha_end <= 65536}
  {line_end:nat | sha_end <= line_end; line_end <= 65536}
  {xml_size:nat | xml_size <= 65536}{feed_size:nat | feed_size <= 1048576}
  (arguments_borrow: !$A.borrow(byte, arguments_loc, 4096), dir_start: int dir_start,
    dir_stop: int dir_stop,
   pins_borrow: !$A.borrow(byte, pins_loc, 65536), name_start: int name_start,
     name_end: int name_end,
   url_start: int url_start, url_end: int url_end, sha_start: int sha_start, sha_end: int sha_end,
   line_end: int line_end,
   xml: !$A.borrow(byte, xml_loc, 65536), xml_size: int xml_size,
   feed: !$A.borrow(byte, feed_loc, 1048576), feed_size: int feed_size,
   out: $B.builder_v): @($B.builder_v, int) = let
  val code = _in_feed(arguments_borrow, dir_start, dir_stop, pins_borrow, name_start, name_end,
    url_start, url_end, sha_start, sha_end, line_end, xml, xml_size, feed, feed_size, out)
in @(out, code) end

(* The line [line_start, line_end) of the pins file: as _in_feed, trying the first
   feed and then the second; 4 when the line is not a pin. The builder is handed
   in and back. *)
fn _repin_line {arguments_loc:agz}{pins_loc:agz}{first_loc:agz}{second_loc:agz}
  {dir_start:nat}{dir_stop:int | dir_start <= dir_stop; dir_stop <= 4096}
  {line_start:nat}{line_end:nat | line_start < line_end; line_end <= 65536}
  {first_size:nat | first_size <= 1048576}{second_size:nat | second_size <= 1048576}
  (arguments_borrow: !$A.borrow(byte, arguments_loc, 4096), dir_start: int dir_start,
    dir_stop: int dir_stop,
   pins_borrow: !$A.borrow(byte, pins_loc, 65536), line_start: int line_start,
     line_end: int line_end,
   first: !$A.borrow(byte, first_loc, 1048576), first_size: int first_size,
   second: !$A.borrow(byte, second_loc, 1048576), second_size: int second_size,
   out: $B.builder_v): @($B.builder_v, int) = let
  val name_end = _token_end(pins_borrow, line_start, line_end)
in
  if name_end <= line_start then @(out, 4)
  else if name_end >= line_end then @(out, 4)
  else let
    val url_start = name_end + 1
    val url_end = _token_end(pins_borrow, url_start, line_end)
  in
    if url_end <= url_start then @(out, 4)
    else if url_end >= line_end then @(out, 4)
    else let
      val sha_start = url_end + 1
      val sha_end = _token_end(pins_borrow, sha_start, line_end)
    in
      if sha_end <= sha_start then @(out, 4)
      else if sha_end >= line_end then @(out, 4)
      else let
        val xml_path = _name_path(pins_borrow, line_start, name_end, ".xml")
        val xml_array = $A.alloc<byte>(65536)
        val xml_size = _read_file(xml_path, xml_array, 65536)
        val @(frozen_xml, xml) = $A.freeze<byte>(xml_array)
        val @(out_after, code) = (if xml_size < 0 then let
            val () = _say_token("android-sdk-pins: ", pins_borrow, line_start, name_end,
              ".xml cannot be read here or is larger than 65535 bytes\n")
          in @(out, 2) end
          else let
            val @(out_first, first_code) = _in_feed_owned(arguments_borrow, dir_start, dir_stop,
              pins_borrow,
              line_start, name_end, url_start, url_end, sha_start, sha_end, line_end, xml, xml_size,
              first, first_size, out)
          in
            if first_code <> 3 then @(out_first, first_code)
            else let
              val @(out_second, second_code) = _in_feed_owned(arguments_borrow, dir_start, dir_stop,
                pins_borrow, line_start, name_end, url_start, url_end, sha_start, sha_end, line_end,
                xml, xml_size, second, second_size, out_first)
            in
              if second_code <> 3 then @(out_second, second_code)
              else let
                val () = _say_token("android-sdk-pins: ", pins_borrow, line_start, name_end,
                  ": no stable revision of the package is in the feeds\n")
              in @(out_second, 2) end
            end
          end): @($B.builder_v, int)
        val () = $A.drop<byte>(frozen_xml, xml)
        val () = $A.free<byte>($A.thaw<byte>(frozen_xml))
      in @(out_after, code) end
    end
  end
end

(* The builder with the pins file's bytes [start, stop) appended, and a newline
   after them when newline is true *)
fn _with_line {pins_loc:agz}{start:nat}{stop:int | start <= stop; stop <= 65536}
  (out: $B.builder_v, pins_borrow: !$A.borrow(byte, pins_loc, 65536), start: int start,
    stop: int stop,
   newline: bool): $B.builder_v = let
  val () = _put_range(pins_borrow, start, stop, 65536, out)
  val () = (if newline then _put(out, 10) else ())
in out end

(* The builder with a newline appended *)
fn _with_newline (out: $B.builder_v): $B.builder_v = let
  val () = _put(out, 10)
in out end

(* The lines of the pins file from start: the file as it is to be written is
   built in out, handed in and back; 0 when no pin moved, 1 when one did, 2 when a
   package cannot be examined, 4 when a line is not a pin *)
fun _repin_lines {arguments_loc:agz}{pins_loc:agz}{first_loc:agz}{second_loc:agz}
  {dir_start:nat}{dir_stop:int | dir_start <= dir_stop; dir_stop <= 4096}
  {start:nat}{size:nat | start <= size; size <= 65535}
  {first_size:nat | first_size <= 1048576}{second_size:nat | second_size <= 1048576}
    .<size - start>.
  (arguments_borrow: !$A.borrow(byte, arguments_loc, 4096), dir_start: int dir_start,
    dir_stop: int dir_stop,
   pins_borrow: !$A.borrow(byte, pins_loc, 65536), start: int start, size: int size,
   first: !$A.borrow(byte, first_loc, 1048576), first_size: int first_size,
   second: !$A.borrow(byte, second_loc, 1048576), second_size: int second_size,
   out: $B.builder_v, moved: int): @($B.builder_v, int) =
  if start >= size then @(out, moved)
  else let
    val line_end = _line_end(pins_borrow, start, size)
    val @(out_line, code) = (if line_end <= start then @(out, 0)
      else if byte2int0($A.read<byte>(pins_borrow, start)) = 35 then @(out, 0)
      else _repin_line(arguments_borrow, dir_start, dir_stop, pins_borrow, start, line_end,
        first, first_size, second, second_size, out)): @($B.builder_v, int)
    val out_copied = (if code = 0 then _with_line(out_line, pins_borrow, start, line_end, false)
      else out_line): $B.builder_v
  in
    if code >= 2 then @(out_copied, code)
    else if line_end >= size then @(out_copied, (if code = 1 then 1 else moved))
    else _repin_lines(arguments_borrow, dir_start, dir_stop, pins_borrow, line_end + 1, size,
      first, first_size, second, second_size, _with_newline(out_copied),
        (if code = 1 then 1 else moved))
  end

(* pins.txt written from the lines built in out when a pin moved (code 1); the exit
   status of the command for the code the lines gave. out is consumed. *)
fn _finish (code: int, out: $B.builder_v): int =
  if code = 1 then let
    var pins_path : $B.builder_v = $B.create()
    val () = _bput(pins_path, "pins.txt")
  in
    if _write_file(pins_path, out) then 0
    else let val () = _say_text("android-sdk-pins: cannot write pins.txt\n") in 1 end
  end
  else let
    val () = $B.builder_free(out)
  in (if code = 0 then 0 else if code = 4 then 2 else 1) end

(* repin <feed-dir>: in the directory of pins.txt. Exit 0: every pin examined (moved
   ones rewritten); 1: a pin cannot be examined or a file cannot be read or written
   (the pins of the lines before it may be written already: the caller discards
   them); 2: pins.txt is not usable. *)
fn _repin {arguments_loc:agz}{dir_start:nat}{dir_stop:int | dir_start <= dir_stop; dir_stop <= 4096}
  (arguments_borrow: !$A.borrow(byte, arguments_loc, 4096), dir_start: int dir_start,
    dir_stop: int dir_stop): int = let
  val pins = $A.alloc<byte>(65536)
  val pins_size = _read_pins(pins)
  val first = $A.alloc<byte>(1048576)
  val first_size = _read_file(_feed_path(arguments_borrow, dir_start, dir_stop,
    "repository2-1.xml"),
    first, 1048576)
  val second = $A.alloc<byte>(1048576)
  val second_size = _read_file(_feed_path(arguments_borrow, dir_start, dir_stop, "sys-img2-1.xml"),
    second, 1048576)
  val @(frozen_pins, pins_borrow) = $A.freeze<byte>(pins)
  val @(frozen_first, first_borrow) = $A.freeze<byte>(first)
  val @(frozen_second, second_borrow) = $A.freeze<byte>(second)
  val status = (if pins_size < 0 then let
      val () = (if pins_size = ~2
        then _say_text("android-sdk-pins: pins.txt is larger than 65535 bytes\n")
        else _say_text("android-sdk-pins: cannot read pins.txt in the current directory\n"))
    in 2 end
    else if first_size < 0 then let
      val () = _say_text("android-sdk-pins: repository2-1.xml: unreadable or over 1048575 bytes\n")
    in 1 end
    else if second_size < 0 then let
      val () = _say_text("android-sdk-pins: sys-img2-1.xml: unreadable or over 1048575 bytes\n")
    in 1 end
    else let
      val @(out, code) = _repin_lines(arguments_borrow, dir_start, dir_stop, pins_borrow, 0,
        pins_size,
        first_borrow, first_size, second_borrow, second_size, $B.create(), 0)
    in _finish(code, out) end): int
  val () = $A.drop<byte>(frozen_pins, pins_borrow)
  val () = $A.free<byte>($A.thaw<byte>(frozen_pins))
  val () = $A.drop<byte>(frozen_first, first_borrow)
  val () = $A.free<byte>($A.thaw<byte>(frozen_first))
  val () = $A.drop<byte>(frozen_second, second_borrow)
  val () = $A.free<byte>($A.thaw<byte>(frozen_second))
in status end

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
  val @(command_start, command_stop) = _argument_range(arguments_borrow, arguments_size, 1)
  val @(feed_start, feed_stop) = _argument_range(arguments_borrow, arguments_size, 2)
  val @(extra_start, _) = _argument_range(arguments_borrow, arguments_size, 3)
  val is_repin = (arguments_size < 4095
    && _is(arguments_borrow, command_start, command_stop, "repin", 4096)): bool
  val status = (if arguments_size < 4095 && _is_key(arguments_borrow, arguments_size) then _key()
    else if is_repin then
      (if feed_stop > feed_start && extra_start >= arguments_size
       then _repin(arguments_borrow, feed_start, feed_stop)
       else let
         val () = _say_text("usage: android-sdk-pins repin <feed-directory>\n")
       in 2 end)
    else if ~usable then let
      val () = _say_text(
        "usage: android-sdk-pins install <sdk-root> | repin <feed-directory> | key\n")
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
