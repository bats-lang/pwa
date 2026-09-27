#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/dom as D
#use widget as W

implement main0 () = let
  val doc = $D.create_document($A.text_lit("div"), 3, $A.text_lit("bats-root"), 9)
  (* The message, added under the root by a diff that apply consumes *)
  val () = $D.apply(doc, $W.AddChild($W.Root(), $W.Text($A.text_lit("BATS PWA"), 8)))
  val () = $D.destroy(doc)
in end
