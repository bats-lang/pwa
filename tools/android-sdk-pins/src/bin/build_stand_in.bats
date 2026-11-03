(* build_stand_in -- the Android build of the tests of build-again (bats-lang/pwa#276;
   area keyword android-gradle-retry, .claude/rules/android-gradle-retry.md): a copy of
   it is run in a case's directory, as the build script and, named gradlew in the
   directory project, as the Gradle wrapper.

   With the argument --stop it appends --stop to the file gradlew-calls and exits 0.
   Otherwise it adds a byte to the file build-count and, while that count is at most
   the number in its argument (the failures to make), prints what Gradle printed when a
   repository did not answer, to stderr, and exits 1. The argument other makes it print
   error: compilation failed to stderr and exit 1 (that text matches no part of the
   retry's pattern). Otherwise it prints one line to stderr, a line to stdout and
   BUILD SUCCESSFUL to stdout, and exits 0. *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use env as E
#use file as F
#use list as L
#use process as P
#use result as R

staload "smoke_files.sats"

(* The process's arguments, NUL-separated, into buffer: their length *)
fn _arguments_read {l:agz} (buffer: !$A.arr(byte, l, 4096)): [size:nat | size <= 4096] int size =
  case+ $E.args_read(buffer, 4096) of
  | ~$R.some(size) => size
  | ~$R.none() => 0

(* The first byte of the first argument after the program's name: ~1 when there is none *)
fn _first_byte {l:agz}{size:nat | size <= 4096} (view: !$A.borrow(byte, l, 4096), size: int size): int = let
  fun skip {l:agz}{size:nat | size <= 4096}{i:nat | i <= size} .<size - i>.
    (view: !$A.borrow(byte, l, 4096), size: int size, i: int i): [r:nat | i <= r; r <= size] int r =
    if i >= size then i
    else if byte2int0($A.read<byte>(view, i)) = 0 then i
    else skip(view, size, i + 1)
  val start = skip(view, size, 0) + 1
in
  if start >= size then ~1 else byte2int0($A.read<byte>(view, start))
end

implement main0 () = let
  val buffer = $A.alloc<byte>(4096)
  val size = _arguments_read(buffer)
  val @(frozen, view) = $A.freeze<byte>(buffer)
  val first = _first_byte(view, size)
  val () = $A.drop<byte>(frozen, view)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in
  if first = 45 then let
    (* --stop *)
    val _ = append_text(path2(".", "gradlew-calls"), text_of("--stop"))
  in () end
  else let
    val _ = append_x(path2(".", "build-count"))
    val count = size_of(path2(".", "build-count"))
    val failures = (if first >= 48 then (if first <= 57 then first - 48 else 0) else 0): int
  in
    if first = 111 then let
      val () = prerr! ("error: compilation failed\n")
    in exit_void(1) end
    else if count <= failures then let
      val () = prerr! ("> Could not find org.jetbrains.kotlin:kotlin-stdlib:2.2.0.\n")
    in exit_void(1) end
    else let
      val () = prerr! ("a line of the build on stderr\n")
      val () = println! ("a line of the build on stdout")
    in println! ("BUILD SUCCESSFUL") end
  end
end
