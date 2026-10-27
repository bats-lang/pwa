#target native
#include "share/atspre_staload.hats"
#use array as A
#use pwa as P

(* The example's PWA and its Android project *)
fn generate (): void = let
  val assets = $A.alloc<byte>(1)
  (* installed, it opens and is shared text files *)
  val () = $P.create_pwa_opening("Example App", "dev.bats.example",
    "dist/release/pwa-web.wasm", "app.wasm", "dist/pwa",
    assets, 0, 1, "text/plain", ".txt")
  val () = $A.free<byte>(assets)
  (* The Capacitor project around it: dist/android/build-android.sh
     builds the Android app *)
  val () = $P.create_android_locked("Example App", "dev.bats.example", "../pwa", "dist/android", "text/plain")
in end

(* build-pwa test [--timings <dir>] [--evidence <dir>] [-- <playwright args>] runs the
   example's e2e suite against dist/pwa (bats-lang/pwa#82); build-pwa
   alone generates it; build-pwa pages SOURCE NAME copies a directory of
   static pages to dist/pwa/NAME (bats-lang/pwa#243); build-pwa values ENVFILE
   OUTFILE NAME:KEY:FORM... writes a JSON file of public values (bats-lang/pwa#244) *)
implement main0 () =
  if $P.test_wanted () then let
    val status = $P.test_run ()
  in if status <> 0 then exit_void (status) else () end
  else if $P.pages_wanted () then let
    val status = $P.pages_run ()
  in if status <> 0 then exit_void (status) else () end
  else if $P.values_wanted () then let
    val status = $P.values_run ()
  in if status <> 0 then exit_void (status) else () end
  else generate ()
