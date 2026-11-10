#include "share/atspre_staload.hats"
#use array as A
#use file as F
#use pwa as P
#use result as R
#use str as S

(* The book forms (create_pwa_book, create_pwa_opening_book; keyword: book
   bridge, bats-lang/pwa#286) write bridge's produce_bridge_app_book, whose
   JS knows the book opcodes 13 to 18 (bookOpEnd has a "case N:" for each).
   The current forms (create_pwa, create_pwa_opening) are called too, with
   their types, and their bridge.js has none of them. For each form this
   prints whether bridge.js is not empty, then a digit for each of the
   opcodes 13 to 18: 1 when the text "case N:" is in the file, else 0.
   `expected` is the output. *)

fun _scan {l:agz}{n:pos}{lp:agz}{np:pos}{k:nat | k <= n}{p:nat | p <= k} .<k - p>.
  (src: !$A.arr(byte, l, n), k: int k, p: int p,
   pat: !$A.borrow(byte, lp, np), np: int np): bool =
  if p + np > k then false
  else if $S.match_at_arr(src, p, pat, np) then true
  else _scan(src, k, p + 1, pat, np)

(* True when "case <d1><d2>:" is in src[0, k) *)
fn _opcode_found {l:agz}{n:pos}{k:nat | k <= n}
  (src: !$A.arr(byte, l, n), k: int k, d1: char, d2: char): bool = let
  var pat = @[char][8]('c', 'a', 's', 'e', ' ', d1, d2, ':')
  val @(fz, bv) = $A.freeze<byte>($S.from_char_array(pat, 8))
  val r = _scan(src, k, 0, bv, 8)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in r end

fn _digit (b: bool): void = if b then print_char('1') else print_char('0')

fn _ops {l:agz}{k:nat | k <= 524288}
  (buf: !$A.arr(byte, l, 524288), k: int k): void = let
  val () = _digit(_opcode_found(buf, k, '1', '3'))
  val () = _digit(_opcode_found(buf, k, '1', '4'))
  val () = _digit(_opcode_found(buf, k, '1', '5'))
  val () = _digit(_opcode_found(buf, k, '1', '6'))
  val () = _digit(_opcode_found(buf, k, '1', '7'))
in _digit(_opcode_found(buf, k, '1', '8')) end

(* The bytes of the file at bp read into buf, none if it did not open *)
fn _read_all {l:agz}{lb:agz}
  (bp: !$A.borrow(byte, lb, 12), buf: !$A.arr(byte, l, 524288)): [k:nat | k <= 524288] int k =
  case+ $F.file_open(bp, 12, $F.ReadOnly(), $F.OpenExisting(), 0) of
  | ~$R.ok(fd) => let
      val k = (case+ $F.file_read(fd, buf, 524288) of
        | ~$R.ok(k) => k | ~$R.err(_) => 0): [k:nat | k <= 524288] int k
      val () = $R.discard<int><$F.io_error>($F.file_close(fd))
    in k end
  | ~$R.err(_) => 0

(* The report of <d>x/bridge.js, d one letter *)
fn _report (label: string, d: char): void = let
  var path = @[char][12](d, 'x', '/', 'b', 'r', 'i', 'd', 'g', 'e', '.', 'j', 's')
  val @(fp, bp) = $A.freeze<byte>($S.from_char_array(path, 12))
  val buf = $A.alloc<byte>(524288)
  val k = _read_all(bp, buf)
  val () = print! (label, ": ", (if k > 0 then 1 else 0): int, " ")
  val () = _ops(buf, k)
  val () = println! ()
  val () = $A.free<byte>(buf)
  val () = $A.drop<byte>(fp, bp)
in $A.free<byte>($A.thaw<byte>(fp)) end

implement main0 () = let
  val assets = $A.alloc<byte>(1)
  val () = $P.create_pwa("Book", "dev.bats.book", "none.wasm", "app.wasm", "ax", assets, 0, 1)
  val () = $P.create_pwa_opening("Book", "dev.bats.book", "none.wasm", "app.wasm", "bx", assets, 0, 1, "application/epub+zip", ".epub")
  val () = $P.create_pwa_book("Book", "dev.bats.book", "none.wasm", "app.wasm", "cx", assets, 0, 1)
  val () = $P.create_pwa_opening_book("Book", "dev.bats.book", "none.wasm", "app.wasm", "dx", assets, 0, 1, "application/epub+zip", ".epub")
  val () = $A.free<byte>(assets)
  val () = _report("create_pwa", 'a')
  val () = _report("create_pwa_opening", 'b')
  val () = _report("create_pwa_book", 'c')
  val () = _report("create_pwa_opening_book", 'd')
in end
