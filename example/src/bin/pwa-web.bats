#target wasm binary
#include "share/atspre_staload.hats"
#use str as S
#use wasm.bats-packages.dev/dom as D
#use widget as W

implement main0 () = let
  var tag = @[char][3]('d', 'i', 'v')
  var mid = @[char][9]('b', 'a', 't', 's', '-', 'r', 'o', 'o', 't')
  val doc = $D.create_document($S.text_of_chars(tag, 3), 3, $S.text_of_chars(mid, 9), 9)
  val root = $W.Element($W.ElementNode($W.Root(), $W.Normal($W.Div()), ~1, 0, $W.NoneInt(), $W.NoneStr(), $W.WNil()))
  val @(_, diff) = $W.add_child(root, $W.Text("BATS PWA"))
  val () = $D.apply(doc, diff)
  val () = $D.destroy(doc)
in end
