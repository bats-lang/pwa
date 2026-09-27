#target native
#include "share/atspre_staload.hats"
#use array as A
#use pwa as P

implement main0 () = let
  val assets = $A.alloc<byte>(1)
  val () = $P.create_pwa("Example App", "dev.bats.example",
    "dist/release/pwa-web.wasm", "app.wasm", "dist/pwa",
    assets, 0, 1)
  val () = $A.free<byte>(assets)
  (* The Capacitor project around it: dist/android/build-android.sh
     builds the Android app *)
  val () = $P.create_android("Example App", "dev.bats.example", "../pwa", "dist/android")
in end
