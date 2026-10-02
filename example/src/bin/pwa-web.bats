#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/dom as D
#use widget as W
staload BE = "wasm.bats-packages.dev/bridge/src/external.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"

fn _literal_bytes {n:pos | n < 256} (text: string n, n: int n): [l:agz] $A.arr(byte, l, n) = let
  val bytes = $A.alloc<byte>(n)
  val () = $A.write_text(bytes, 0, $A.text_lit(text), n)
in bytes end

fn _release_bytes {l:agz}{n:nat}
  (frozen: $A.frozenx(byte, l, n, 1, null), borrowed: $A.borrow(byte, l, n)): void = let
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

fn _at_most_200 {name_len:pos} (name_len: int name_len): [shown_len:pos | shown_len <= 200; shown_len <= name_len] int shown_len =
  if name_len > 200 then 200 else name_len

(* The element opened, under the root, where the name of the last file
   handed to the app from outside it is shown *)
fn _opened_make (): void = let
  val doc = $D.open_document($A.text_lit("bats-root"), 9)
  val @(root_frozen, root_bytes) = $A.freeze<byte>(_literal_bytes("bats-root", 9))
  val @(opened_frozen, opened_bytes) = $A.freeze<byte>(_literal_bytes("opened", 6))
  val () = $D.add_element(doc, root_bytes, 9, opened_bytes, 6, $D.P)
  val () = _release_bytes(opened_frozen, opened_bytes)
  val () = _release_bytes(root_frozen, root_bytes)
in $D.destroy(doc) end

(* Shows name[0, name_len) in the element opened *)
fn _opened_show {l:agz}{name_len:pos | name_len < 65536}
  (name: $A.arr(byte, l, name_len), name_len: int name_len): void = let
  val doc = $D.open_document($A.text_lit("bats-root"), 9)
  val @(opened_frozen, opened_bytes) = $A.freeze<byte>(_literal_bytes("opened", 6))
  val @(name_frozen, name_bytes) = $A.freeze<byte>(name)
  val () = $D.set_text(doc, opened_bytes, 6, name_bytes, 0, name_len)
  val () = _release_bytes(name_frozen, name_bytes)
  val () = _release_bytes(opened_frozen, opened_bytes)
in $D.destroy(doc) end

(* The name of a file handed to the app from outside it, shown when it
   has one *)
fn _name_show (name: $R.option([k:nat] $BD.dblob(k))): void =
  case+ name of
  | ~$R.none() => ()
  | ~$R.some(blob) => let
      val name_len = $BD.blob_len(blob)
    in
      if name_len <= 0 then $BD.blob_free(blob)
      else let
        val shown_len = _at_most_200(name_len)
        val shown = $A.alloc<byte>(shown_len)
        val () = $BD.blob_read(blob, 0, shown, shown_len)
        val () = $BD.blob_free(blob)
      in _opened_show(shown, shown_len) end
    end

(* A file handed to the app from outside it (the system opens the app
   with it, or shares it with the app): its name is shown *)
fn _external_file (handed: $BE.external): void =
  case+ handed of
  | ~$BE.External(file, name) => let
      val () = _name_show(name)
    in $BF.file_close(file) end
  | ~$BE.ExternalUnreadable(name) => _name_show(name)

(* How many files handed to the app are shown in a session, one after
   another. A metric needs the bound *)
#define EXTERNAL_ROUNDS 100000

(* Shows each file handed to the app as it comes, the next asked for
   when the last one is shown *)
fun _external_wait {rounds:nat} .<rounds>. (rounds: int rounds): void =
  if rounds <= 0 then ()
  else $P.finish<Int>($P.and_then<$BE.external><Int>($BE.external_next(), llam(handed) => let
      val () = _external_file(handed)
    in $P.ret<Int>(0) end), llam(_) => _external_wait(rounds - 1))

implement main0 () = let
  val doc = $D.create_document($A.text_lit("div"), 3, $A.text_lit("bats-root"), 9)
  (* The message, added under the root by a diff that apply consumes *)
  val () = $D.apply(doc, $W.AddChild($W.Root(), $W.Text($A.text_lit("BATS PWA"), 8)))
  val () = $D.destroy(doc)
  val () = _opened_make()
  (* Files the system opens the app with reach it through the bridge *)
  val () = _external_wait(EXTERNAL_ROUNDS)
in end
