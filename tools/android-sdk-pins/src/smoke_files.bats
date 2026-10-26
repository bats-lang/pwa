(* smoke_files -- what the tests of the smoke test's retry (bats-lang/pwa#214; area
   keyword android-smoke, .claude/rules/android-smoke.md) and their stand-in
   programs share: files by a path made of text, and running a program.
   They belong to the tests only, and android-sdk-pins itself does not use them. *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use env as E
#use file as F
#use list as L
#use process as P
#use result as R

(* first, a slash, then second, as a builder *)
#pub fn path2 {a,b:nat | a < 2000; b < 2000} (first: string a, second: string b): $B.builder_v

implement path2 (first, second) = let
  var out : $B.builder(0) = $B.create()
  val () = $B.bput(out, first)
  val () = $B.bput(out, "/")
  val () = $B.bput(out, second)
in out end

(* text as a builder *)
#pub fn text_of {a:nat | a < 4000} (text: string a): $B.builder_v

implement text_of (text) = let
  var out : $B.builder(0) = $B.create()
  val () = $B.bput(out, text)
in out end

(* the builder's text as one argument *)
#pub fn arg_of (text: $B.builder_v): $P.arg_entry

implement arg_of (text) = let
  val @(array, size) = $B.into_arr(text)
in @(array, size) end

#pub fn arg_text {a:nat | a < 4000} (text: string a): $P.arg_entry

implement arg_text (text) = arg_of(text_of(text))

(* The path (a builder, its text then a zero byte) opened with access and opening: the
   file, else none. The builder is consumed. *)
fn _open (path: $B.builder_v, access: $F.access, opening: $F.opening): $R.result($F.fd, $F.io_error) = let
  var with_zero : $B.builder_v = path
  val () = (if $B.length(with_zero) < 524288 then $B.put_byte(with_zero, 0) else ())
  val @(array, _) = $B.to_arr(with_zero)
  val @(frozen, view) = $A.freeze<byte>(array)
  val opened = $F.file_open(view, 524288, access, opening, 420)
  val () = $A.drop<byte>(frozen, view)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in opened end

(* The size of the file, 0 when it is not there *)
#pub fn size_of (path: $B.builder_v): int

implement size_of (path) =
  case+ _open(path, $F.ReadOnly(), $F.OpenExisting()) of
  | ~$R.err(_) => 0
  | ~$R.ok(fd) => let
      val size = (case+ $F.fd_size(fd) of | ~$R.ok(s) => s | ~$R.err(_) => 0): int
      val () = $R.discard<int><$F.io_error>($F.file_close(fd))
    in size end

(* One byte added at the end of the file (made when it is not there) *)
#pub fn append_x (path: $B.builder_v): bool

implement append_x (path) =
  case+ _open(path, $F.WriteOnly(), $F.CreateOrAppend()) of
  | ~$R.err(_) => false
  | ~$R.ok(fd) => let
      val one = $A.alloc<byte>(1)
      val () = $A.set<byte>(one, 0, int2byte0(120))
      val @(frozen, view) = $A.freeze<byte>(one)
      val written = $F.file_write(fd, view, 1)
      val () = $A.drop<byte>(frozen, view)
      val () = $A.free<byte>($A.thaw<byte>(frozen))
      val () = $R.discard<int><$F.io_error>($F.file_close(fd))
    in (case+ written of | ~$R.ok(_) => true | ~$R.err(_) => false) end

(* The file made (or emptied) to hold the text *)
#pub fn write_text (path: $B.builder_v, text: $B.builder_v): bool

fun _copy_to {l,k:agz}{cap:pos}{n:pos | n <= cap}{i:nat | i <= n} .<n - i>.
  (source: !$A.borrow(byte, l, cap), destination: !$A.arr(byte, k, n), size: int n, i: int i): void =
  if i >= size then ()
  else let
    val () = $A.set<byte>(destination, i, $A.read<byte>(source, i))
  in _copy_to(source, destination, size, i + 1) end

implement write_text (path, text) =
  case+ _open(path, $F.WriteOnly(), $F.CreateOrTruncate()) of
  | ~$R.err(_) => let val () = $B.builder_free(text) in false end
  | ~$R.ok(fd) => let
      val @(array, size) = $B.to_arr(text)
      val @(frozen, view) = $A.freeze<byte>(array)
      val written = (if size > 0 then let
          val exact = $A.alloc<byte>(size)
          val () = _copy_to(view, exact, size, 0)
          val @(exact_frozen, exact_view) = $A.freeze<byte>(exact)
          val result = (case+ $F.file_write(fd, exact_view, size) of | ~$R.ok(_) => true | ~$R.err(_) => false): bool
          val () = $A.drop<byte>(exact_frozen, exact_view)
          val () = $A.free<byte>($A.thaw<byte>(exact_frozen))
        in result end
        else true): bool
      val () = $A.drop<byte>(frozen, view)
      val () = $A.free<byte>($A.thaw<byte>(frozen))
      val () = $R.discard<int><$F.io_error>($F.file_close(fd))
    in written end

(* The file's bytes into buffer (131072 bytes): how many, ~1 when it cannot be read whole *)
#pub fn read_into {l:agz} (path: $B.builder_v, buffer: !$A.arr(byte, l, 131072)): [k:int | ~1 <= k; k <= 131072] int k

implement read_into (path, buffer) =
  case+ _open(path, $F.ReadOnly(), $F.OpenExisting()) of
  | ~$R.err(_) => ~1
  | ~$R.ok(fd) => let
      val size = (case+ $F.fd_size(fd) of | ~$R.ok(s) => s | ~$R.err(_) => ~1): int
      val count = (if size < 0 then ~1
        else if size >= 131072 then ~1
        else (case+ $F.file_read(fd, buffer, 131072) of
          | ~$R.ok(k) => (if k = size then k else ~1)
          | ~$R.err(_) => ~1)): [k:int | ~1 <= k; k <= 131072] int k
      val () = $R.discard<int><$F.io_error>($F.file_close(fd))
    in count end

(* Whether the bytes of view from place start with the literal *)
fn _matches_at {l:agz}{size:nat | size <= 131072}{place:nat | place <= size}{literal_size:nat}
  (view: !$A.borrow(byte, l, 131072), size: int size, place: int place, literal: string literal_size): bool = let
  val literal_length = g1u2i(string1_length(literal))
  fun loop {l:agz}{size:nat | size <= 131072}{place:nat | place <= size}{literal_size:nat}{j:nat | j <= literal_size} .<literal_size - j>.
    (view: !$A.borrow(byte, l, 131072), size: int size, place: int place,
     literal: string literal_size, literal_length: int literal_size, j: int j): bool =
    if j >= literal_length then true
    else if place + j >= size then false
    else if byte2int0($A.read<byte>(view, place + j)) <> char2int0(string_get_at(literal, j)) then false
    else loop(view, size, place, literal, literal_length, j + 1)
in loop(view, size, place, literal, literal_length, 0) end

#pub fn matches_at {l:agz}{size:nat | size <= 131072}{place:nat | place <= size}{literal_size:nat}
  (view: !$A.borrow(byte, l, 131072), size: int size, place: int place, literal: string literal_size): bool

implement matches_at (view, size, place, literal) = _matches_at(view, size, place, literal)

fun _find_from {l:agz}{size:nat | size <= 131072}{at:nat | at <= size}{literal_size:nat} .<size - at>.
  (view: !$A.borrow(byte, l, 131072), size: int size, at: int at, literal: string literal_size)
  : [place:int | ~1 <= place; place <= size] int place =
  if at >= size then ~1
  else if _matches_at(view, size, at, literal) then at
  else _find_from(view, size, at + 1, literal)

(* The first place at or after from where the literal is, ~1 when there is none *)
#pub fn find_from {l:agz}{size:nat | size <= 131072}{from:nat | from <= size}{literal_size:nat}
  (view: !$A.borrow(byte, l, 131072), size: int size, from: int from, literal: string literal_size)
  : [place:int | ~1 <= place; place <= size] int place

implement find_from (view, size, from, literal) = _find_from(view, size, from, literal)

(* program (found on PATH) with the arguments after its own name and the NAME=VALUE
   entries of extra added to the environment, the streams shared: its exit status,
   ~1 when it could not be run *)
#pub fn run_program {p:nat | p < 4000}
  (program: string p, args: $L.listv($P.arg_entry), extra: $L.listv($P.arg_entry)): int

implement run_program (program, args, extra) = let
  val @(nul | path) = $P.path_of_string_proved(program)
  val @(frozen, view) = $A.barr_freeze(path)
  val argv = $L.list_vt_cons(arg_text(program), args)
  val spawned = $P.spawn_inherit_env_with_proved(nul | view, argv, extra, $P.inherit(), $P.inherit(), $P.inherit())
  val () = $A.cborrow_drop(frozen, view)
  val () = $A.barr_free($A.barr_thaw(frozen))
in
  case+ spawned of
  | ~$R.ok(spawned_process) => let
      val+ ~$P.spawn_pipes_mk(child, stdin_pipe, stdout_pipe, stderr_pipe) = spawned_process
      val () = $P.pipe_end_close(stdin_pipe)
      val () = $P.pipe_end_close(stdout_pipe)
      val () = $P.pipe_end_close(stderr_pipe)
    in (case+ $P.child_wait(child) of | ~$R.ok(code) => code | ~$R.err(_) => ~1) end
  | ~$R.err(_) => ~1
end

(* As run_program, the standard output (at most 4096 bytes) read: whether its
   bytes are the literal then a newline, then the status *)
#pub fn run_says {p:nat | p < 4000}{literal_size:nat | literal_size < 4000}
  (program: string p, args: $L.listv($P.arg_entry), extra: $L.listv($P.arg_entry),
   literal: string literal_size): @(int, bool)

implement run_says (program, args, extra, literal) = let
  val @(nul | path) = $P.path_of_string_proved(program)
  val @(frozen, view) = $A.barr_freeze(path)
  val argv = $L.list_vt_cons(arg_text(program), args)
  val spawned = $P.spawn_inherit_env_with_proved(nul | view, argv, extra, $P.inherit(), $P.pipe_new(), $P.inherit())
  val () = $A.cborrow_drop(frozen, view)
  val () = $A.barr_free($A.barr_thaw(frozen))
in
  case+ spawned of
  | ~$R.ok(spawned_process) => let
      val+ ~$P.spawn_pipes_mk(child, stdin_pipe, stdout_pipe, stderr_pipe) = spawned_process
      val () = $P.pipe_end_close(stdin_pipe)
      val () = $P.pipe_end_close(stderr_pipe)
      val+ ~$P.pipe_fd(stdout_fd) = stdout_pipe
      val buffer = $A.alloc<byte>(131072)
      val count = (case+ $F.file_read(stdout_fd, buffer, 131072) of
        | ~$R.ok(k) => k | ~$R.err(_) => 0): [k:nat | k <= 131072] int k
      val () = $R.discard<int><$F.io_error>($F.file_close(stdout_fd))
      val code = (case+ $P.child_wait(child) of | ~$R.ok(c) => c | ~$R.err(_) => ~1): int
      val @(frozen_buffer, buffer_view) = $A.freeze<byte>(buffer)
      val expected = g1u2i(string1_length(literal))
      val same = (count = expected + 1 && matches_at(buffer_view, count, 0, literal)
        && byte2int0($A.read<byte>(buffer_view, expected)) = 10): bool
      val () = $A.drop<byte>(frozen_buffer, buffer_view)
      val () = $A.free<byte>($A.thaw<byte>(frozen_buffer))
    in @(code, same) end
  | ~$R.err(_) => @(~1, false)
end
