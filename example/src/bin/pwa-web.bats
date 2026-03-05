#target wasm binary
#include "share/atspre_staload.hats"
#use str as S
#use wasm.bats-packages.dev/dom as D
#use widget as W

implement main0 () = let
  var mt = @[char][3]('d','i','v')
  val mount_tag = $S.text_of_chars(mt, 3)
  var mi = @[char][9]('b','a','t','s','-','r','o','o','t')
  val mount_id = $S.text_of_chars(mi, 9)
  val doc = $D.create_document(mount_tag, 3, mount_id, 9)
  var mc = @[char][3]('m','s','g')
  val msg_id_t = $S.text_of_chars(mc, 3)
  val msg_id = $W.Generated(msg_id_t, 3)
  val msg = $W.Element($W.ElementNode(
    msg_id, $W.Normal($W.Div()), ~1, 0,
    $W.NoneInt(), $W.NoneStr(),
    $W.WCons($W.Text("BATS PWA"), $W.WNil())))
  val d = $W.AddChild($W.Root(), msg)
  val () = $D.apply(doc, d)
  val () = $D.destroy(doc)
in end
