#include "share/atspre_staload.hats"
#use array as A
#use file as F
#use pwa as P
#use result as R
#use str as S

(* create_pwa copies each asset in a NUL-separated list into out_dir
   under its basename. Two assets: in/one.txt (nested path) and two.css
   (no directory). The copies must hold the same bytes. Open flags are
   Linux values, as elsewhere in bats-lang for now. *)

fn _write {n:pos | n < 1048576}{m:pos | m <= 1048576}
  (path: &(@[char][n]), n: int n, body: &(@[char][m]), m: int m): void = let
  val @(fp, bp) = $A.freeze<byte>($S.from_char_array(path, n))
  val @(fb, bb) = $A.freeze<byte>($S.from_char_array(body, m))
  val () = (case+ $F.file_open(bp, n, 577, 420) of
    | ~$R.ok(fd) => let
        val () = $R.discard<int(m)><int>($F.file_write(fd, bb, m))
      in $R.discard<int><int>($F.file_close(fd)) end
    | ~$R.err(_) => ()): void
  val () = $A.drop<byte>(fp, bp)
  val () = $A.free<byte>($A.thaw<byte>(fp))
  val () = $A.drop<byte>(fb, bb)
in $A.free<byte>($A.thaw<byte>(fb)) end

(* Bytes read from an open result into buf, or ~1 if it failed. *)
fn _read {l:agz} (r: $R.result($F.fd, int), buf: !$A.arr(byte, l, 64)): [k:int | ~1 <= k; k <= 64] int k =
  case+ r of
  | ~$R.ok(fd) => let
      val k = (case+ $F.file_read(fd, buf, 64) of
        | ~$R.ok(k) => k | ~$R.err(_) => 0): [k:nat | k <= 64] int k
      val () = $R.discard<int><int>($F.file_close(fd))
    in k end
  | ~$R.err(_) => ~1

fun _pr {l:agz}{i:nat | i <= 64} .<64 - i>. (buf: !$A.arr(byte, l, 64), i: int i, k: int): void =
  if i >= 64 then () else if i >= k then ()
  else let val () = print_char(int2char0(byte2int0($A.get<byte>(buf, i)))) in _pr(buf, i + 1, k) end

(* Prints path: <length> [<bytes>], or path: missing. *)
fn _show {n:pos | n < 1048576} (label: string, path: &(@[char][n]), n: int n): void = let
  val @(fp, bp) = $A.freeze<byte>($S.from_char_array(path, n))
  val buf = $A.alloc<byte>(64)
  val k = _read($F.file_open(bp, n, 0, 0), buf)
  val () = (if k < 0 then println! (label, ": missing")
            else print! (label, ": ", k, " [")): void
  val () = _pr(buf, 0, k)
  val () = (if k >= 0 then println! ("]") else ()): void
  val () = $A.free<byte>(buf)
  val () = $A.drop<byte>(fp, bp)
in $A.free<byte>($A.thaw<byte>(fp)) end

implement main0 () = let
  var d_in = @[char][2]('i', 'n')
  val @(fd0, bd0) = $A.freeze<byte>($S.from_char_array(d_in, 2))
  val () = $R.discard<int><int>($F.file_mkdir(bd0, 2, 493))
  val () = $A.drop<byte>(fd0, bd0)
  val () = $A.free<byte>($A.thaw<byte>(fd0))
  var p1 = @[char][10]('i', 'n', '/', 'o', 'n', 'e', '.', 't', 'x', 't')
  var c1 = @[char][6]('h', 'e', 'l', 'l', 'o', '\n')
  val () = _write(p1, 10, c1, 6)
  var p2 = @[char][7]('t', 'w', 'o', '.', 'c', 's', 's')
  var c2 = @[char][4]('b', '\173', '\175', '\n')
  val () = _write(p2, 7, c2, 4)
  (* "in/one.txt\0two.css\0" *)
  var al = @[char][19]('i', 'n', '/', 'o', 'n', 'e', '.', 't', 'x', 't', '\000',
                       't', 'w', 'o', '.', 'c', 's', 's', '\000')
  val assets = $S.from_char_array(al, 19)
  val () = $P.create_pwa("Assets Test", "dev.bats.assets", "none.wasm", "app.wasm", "out", assets, 19, 19)
  val () = $A.free<byte>(assets)
  var o1 = @[char][11]('o', 'u', 't', '/', 'o', 'n', 'e', '.', 't', 'x', 't')
  val () = _show("out/one.txt", o1, 11)
  var o2 = @[char][11]('o', 'u', 't', '/', 't', 'w', 'o', '.', 'c', 's', 's')
  val () = _show("out/two.css", o2, 11)
  var o3 = @[char][10]('o', 'u', 't', '/', 'i', 'n', '/', 'o', 'n', 'e')
  val () = _show("out/in/one", o3, 10)
in end
