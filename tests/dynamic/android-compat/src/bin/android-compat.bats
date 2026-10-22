#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use pwa as P

(* build_android_script keeps its published type and text (bats-lang/pwa#131,
   .claude/rules/android-lock.md): the bare "pnpm install" form is what
   apps that have no lock yet still generate, for one published version.
   This prints it for web_dir "../pwa"; `expected` is the text of the
   function in origin/main before the locked form was added beside it, so
   a change to the old form fails here. *)
fun _print {l:agz}{cap:pos}{n:nat | n <= cap}{i:nat | i <= n} .<n - i>.
  (a: !$A.arr(byte, l, cap), n: int n, i: int i): void =
  if i >= n then ()
  else let
    val () = print_char(int2char0(byte2int0($A.get<byte>(a, i))))
  in _print(a, n, i + 1) end

implement main0 () = let
  var b = $B.create()
  val () = $P.build_android_script(b, "../pwa")
  val @(a, n) = $B.into_arr(b)
  val () = _print(a, n, 0)
in $A.free<byte>(a) end
