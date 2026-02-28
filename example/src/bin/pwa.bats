(* pwa-example -- generate PWA shell files into dist/pwa/ *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use file as F
#use pwa as P
#use result as R

fn _write_to {nd:nat}{nf:nat}
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
  val fr = $F.file_open(bvp, $AR.checked_arr_size(pl), 577, 420)
in
  (case+ fr of
  | ~$R.ok(fd) => let
      val wr = $F.file_write(fd, bvc, $AR.checked_arr_size(cl))
      val () = $R.discard<int><int>(wr)
      val cr = $F.file_close(fd)
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
  val mr = $F.file_mkdir(bvd, $AR.checked_arr_size(dl), 493)
  val () = $R.discard<int><int>(mr)
in
  $A.drop<byte>(fzd, bvd); $A.free<byte>($A.thaw<byte>(fzd))
end

implement main0 () = let
  val () = _mkdir("dist")
  val () = _mkdir("dist/pwa")

  val html_b = $B.create()
  val () = $P.build_html(html_b, "BATS PWA", "output.wasm")
  val () = _write_to("dist/pwa", "index.html", html_b)

  val sw_b = $B.create()
  val () = $P.build_service_worker(sw_b, "output.wasm")
  val () = _write_to("dist/pwa", "service-worker.js", sw_b)

  val mf_b = $B.create()
  val () = $P.build_manifest(mf_b, "BATS PWA")
  val () = _write_to("dist/pwa", "manifest.json", mf_b)

  val () = println! ("PWA generated in dist/pwa/")
in end
