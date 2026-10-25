#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use pwa as P

(* The old forms keep their published types and the text they had before
   bats-lang/pwa#201 (android-smoke), for one published version:
   build_smoke_test_script (without the font scale step, pwa#154; removed by
   pwa#189) and build_smoke_test_script_font_scale (type 15000, shown() polling
   uiautomator dump; removed by pwa#203), beside build_smoke_test_script_font_scale_devtools
   (type 16000, every console error a failure; removed by pwa#209) and the new
   build_smoke_test_script_font_scale_devtools_early_event (pwa#207). This prints the three
   old forms for the app id "dev.bats.example", each after a line of '=' signs;
   `expected` is the first two as they were on main before pwa#201 and the third as it
   was on main before pwa#207, so an edit that drops an old form, or puts the DevTools
   shown() or the step in the first, or the classification of the early event in the
   third, fails here. *)
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
  val () = $A.free<byte>(a)
  var b2 = $B.create()
  val () = $P.build_smoke_test_script_font_scale(b2, "dev.bats.example")
  val @(a2, n2) = $B.into_arr(b2)
  val () = println! ("==========")
  val () = _print(a2, n2, 0)
  val () = $A.free<byte>(a2)
  var b3 = $B.create()
  val () = $P.build_smoke_test_script_font_scale_devtools(b3, "dev.bats.example")
  val @(a3, n3) = $B.into_arr(b3)
  val () = println! ("==========")
  val () = _print(a3, n3, 0)
in $A.free<byte>(a3) end
