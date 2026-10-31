#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use pwa as P

(* The old forms keep their published types and the text they had before
   bats-lang/pwa#201 (android-smoke), for one published version:
   build_smoke_test_script_font_scale (type 15000, shown() polling
   uiautomator dump; removed by pwa#203), beside the new
   build_smoke_test_script_font_scale_devtools. This prints that old form
   for the app id "dev.bats.example"; `expected` is its script as it was on
   main before pwa#201, so an edit that drops the form, or puts the DevTools
   shown() in it, fails here. After a line of '=' signs it prints
   build_smoke_test_script_font_scale_devtools (pwa#205, removed by pwa#218),
   the form before the probes step of build_smoke_test_script_probes, as it was
   on main before pwa#205. After a second line of '=' signs it prints
   build_smoke_test_script_probes (pwa#267, removed by pwa#270), the form
   before the font scales of build_smoke_test_script_scaled_probes. (The form without the
   font scale step was removed by pwa#189.) *)
fun _print {l:agz}{cap:pos}{n:nat | n <= cap}{i:nat | i <= n} .<n - i>.
  (a: !$A.arr(byte, l, cap), n: int n, i: int i): void =
  if i >= n then ()
  else let
    val () = print_char(int2char0(byte2int0($A.get<byte>(a, i))))
  in _print(a, n, i + 1) end

implement main0 () = let
  var b2 = $B.create()
  val () = $P.build_smoke_test_script_font_scale(b2, "dev.bats.example")
  val @(a2, n2) = $B.into_arr(b2)
  val () = _print(a2, n2, 0)
  val () = $A.free<byte>(a2)
  var b3 = $B.create()
  val () = $P.build_smoke_test_script_font_scale_devtools(b3, "dev.bats.example")
  val @(a3, n3) = $B.into_arr(b3)
  val () = println! ("==========")
  val () = _print(a3, n3, 0)
  val () = $A.free<byte>(a3)
  var b4 = $B.create()
  val () = $P.build_smoke_test_script_probes(b4, "dev.bats.example")
  val @(a4, n4) = $B.into_arr(b4)
  val () = println! ("==========")
  val () = _print(a4, n4, 0)
in $A.free<byte>(a4) end
