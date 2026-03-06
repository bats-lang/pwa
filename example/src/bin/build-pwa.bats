#target native
#include "share/atspre_staload.hats"
#use array as A
#use pwa as P

implement main0 () = let
  val assets = $A.alloc<byte>(1)
  val () = $P.create_pwa("Example App", "dev.bats.example",
    "dist/wasm/app.wasm", "app.wasm", "dist/pwa",
    assets, 0, 1)
  val () = $A.free<byte>(assets)
in end
