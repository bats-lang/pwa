#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use pwa as P

(* build_smoke_test_script keeps its published type and its text without the
   font scale step (bats-lang/pwa#154, android-smoke): the step is in
   build_smoke_test_script_font_scale beside it, for one published version.
   This prints the old form for the app id "dev.bats.example"; `expected`
   is that script, and it holds no font_scale 1.3, so an edit that drops the
   old form or puts the step in it fails here. *)
fun _print {l:agz}{cap:pos}{n:nat | n <= cap}{i:nat | i <= n} .<n - i>.
  (a: !$A.arr(byte, l, cap), n: int n, i: int i): void =
  if i >= n then ()
  else let
    val () = print_char(int2char0(byte2int0($A.get<byte>(a, i))))
  in _print(a, n, i + 1) end

implement main0 () = let
  var b = $B.create()
  val () = $P.build_smoke_test_script(b, "dev.bats.example")
  val @(a, n) = $B.into_arr(b)
  val () = _print(a, n, 0)
in $A.free<byte>(a) end
