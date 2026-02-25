(* app -- minimal WASM app that displays "BATS PWA" *)
#target wasm

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use css as C
#use wasm.bats-packages.dev/dom as D
#use widget as W

implement main0 () = let
  (* Create document mounted at <div id="app"> *)
  val doc = $D.create_document(
    $A.text_of_chars(3, @[char][3]('d', 'i', 'v')), 3,
    $A.text_of_chars(3, @[char][3]('a', 'p', 'p')), 3)
  (* Create a text widget saying "BATS PWA" *)
  val txt = $W.Text("BATS PWA")
  val root_id = $W.WidgetId(0)
  val diff = $W.AddChild(root_id, txt)
  val () = $D.apply(doc, diff)
  val () = $D.destroy(doc)
in end
