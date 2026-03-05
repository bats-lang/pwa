#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
staload "wasm.bats-packages.dev/bridge/src/dom.bats"

implement main0 () = let
  val buf = $A.alloc<byte>(64)
  (* SET_TEXT opcode = 1
     Wire: [1:u8][nid_len:u16le][nid_str][text_len:u16le][text_str]
     nid = "bats-root" (9 bytes), text = "BATS PWA" (8 bytes)
     Total = 1 + 2 + 9 + 2 + 8 = 22 bytes *)
  val () = $A.write_byte(buf, 0, 1)
  val () = $A.write_u16le(buf, 1, 9)
  (* "bats-root" *)
  val () = $A.write_byte(buf, 3, 98)
  val () = $A.write_byte(buf, 4, 97)
  val () = $A.write_byte(buf, 5, 116)
  val () = $A.write_byte(buf, 6, 115)
  val () = $A.write_byte(buf, 7, 45)
  val () = $A.write_byte(buf, 8, 114)
  val () = $A.write_byte(buf, 9, 111)
  val () = $A.write_byte(buf, 10, 111)
  val () = $A.write_byte(buf, 11, 116)
  val () = $A.write_u16le(buf, 12, 8)
  (* "BATS PWA" *)
  val () = $A.write_byte(buf, 14, 66)
  val () = $A.write_byte(buf, 15, 65)
  val () = $A.write_byte(buf, 16, 84)
  val () = $A.write_byte(buf, 17, 83)
  val () = $A.write_byte(buf, 18, 32)
  val () = $A.write_byte(buf, 19, 80)
  val () = $A.write_byte(buf, 20, 87)
  val () = $A.write_byte(buf, 21, 65)
  val () = dom_flush(buf, 22)
  val () = $A.free<byte>(buf)
in end
