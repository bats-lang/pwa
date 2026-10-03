#target native
#include "share/atspre_staload.hats"
#use array as A
#use pwa as P

implement main0 () = let
  val assets = $A.alloc<byte>(1)
  (* installed, it opens and is shared text files *)
  val () = $P.create_pwa_opening("Example App", "dev.bats.example",
    "dist/release/pwa-web.wasm", "app.wasm", "dist/pwa",
    assets, 0, 1, "text/plain", ".txt")
  val () = $A.free<byte>(assets)
  (* The Capacitor project around it: dist/android/build-android.sh
     builds the Android app, which is also opened at example:// addresses
     (as an OAuth sign-in comes back) *)
  val () = $P.create_android_linked("Example App", "dev.bats.example", "../pwa", "dist/android", "text/plain", "example")
in end
