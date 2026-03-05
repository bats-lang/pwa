#target wasm
#include "share/atspre_staload.hats"
#use str as S
#use wasm.bats-packages.dev/dom as D
#use widget as W

implement main0 () = let
  var tag = @[char][3]('d', 'i', 'v')
  var mid = @[char][9]('b', 'a', 't', 's', '-', 'r', 'o', 'o', 't')
  val doc = $D.create_document($S.text_of_chars(tag, 3), 3, $S.text_of_chars(mid, 9), 9)
  val () = $D.apply(doc, $W.AddChild($W.Root(), $W.Text("BATS PWA")))
  val () = $D.destroy(doc)
in end
