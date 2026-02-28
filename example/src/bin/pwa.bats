(* pwa-example -- generate PWA shell files into dist/pwa/ *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use file as F
#use pwa as P
#use result as R

fn _write_file {nd:nat}{nf:nat}
  (dir: string nd, filename: string nf, content: $B.builder): void = let
  val pb = $B.create()
  val () = $B.bput(pb, dir)
  val () = $B.put_byte(pb, 47)
  val () = $B.bput(pb, filename)
  val () = $B.put_byte(pb, 0)
  val @(pa, pl) = $B.to_arr(pb)
  val @(fzp, bvp) = $A.freeze<byte>(pa)
  val @(ca, cl) = $B.to_arr(content)
  val @(fzc, bvc) = $A.freeze<byte>(ca)
  val fr = $F.file_open(bvp, 524288, 577, 420)
in
  (case+ fr of
  | ~$R.ok(fd) => let
      val bw = $F.buf_writer_create(fd)
      fun write_loop {l:agz}{fuel:nat} .<fuel>.
        (bw: !$F.buf_writer, bv: !$A.borrow(byte, l, 524288),
         i: int, lim: int, fuel: int fuel): void =
        if fuel <= 0 then ()
        else if i >= lim then ()
        else let
          val b = byte2int0($A.read<byte>(bv, $AR.checked_idx(i, 524288)))
          val wr = $F.buf_write_byte(bw, b)
          val () = $R.discard<int><int>(wr)
        in write_loop(bw, bv, i + 1, lim, fuel - 1) end
      val () = write_loop(bw, bvc, 0, cl, $AR.checked_nat(cl + 1))
      val cr = $F.buf_writer_close(bw)
      val () = $R.discard<int><int>(cr)
    in end
  | ~$R.err(_) => ());
  $A.drop<byte>(fzc, bvc); $A.free<byte>($A.thaw<byte>(fzc));
  $A.drop<byte>(fzp, bvp); $A.free<byte>($A.thaw<byte>(fzp))
end

fn _mkdir {nd:nat} (dir: string nd): void = let
  val db = $B.create()
  val () = $B.bput(db, dir)
  val () = $B.put_byte(db, 0)
  val @(da, dl) = $B.to_arr(db)
  val @(fzd, bvd) = $A.freeze<byte>(da)
  val mr = $F.file_mkdir(bvd, 524288, 493)
  val () = $R.discard<int><int>(mr)
in
  $A.drop<byte>(fzd, bvd); $A.free<byte>($A.thaw<byte>(fzd))
end

implement main0 () = let
  val () = _mkdir("dist")
  val () = _mkdir("dist/pwa")

  val html_b = $B.create()
  val () = $P.build_html(html_b, "BATS PWA", "output.wasm")
  val () = _write_file("dist/pwa", "index.html", html_b)

  val sw_b = $B.create()
  val () = $P.build_service_worker(sw_b, "output.wasm")
  val () = _write_file("dist/pwa", "service-worker.js", sw_b)

  val mf_b = $B.create()
  val () = $P.build_manifest(mf_b, "BATS PWA")
  val () = _write_file("dist/pwa", "manifest.json", mf_b)

  val () = println! ("PWA generated in dist/pwa/")
in end
