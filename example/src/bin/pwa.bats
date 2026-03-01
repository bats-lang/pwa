(* pwa-example -- generate PWA shell files into dist/pwa/ *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use file as F
#use pwa as P
#use result as R

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
      val _ = $F.file_write(fd, bvc, $AR.checked_arr_size(cl))
      val _ = $F.file_close(fd)
    in end
  | ~$R.err(_) => ());
  $A.drop<byte>(fzc, bvc); $A.free<byte>($A.thaw<byte>(fzc));
  $A.drop<byte>(fzp, bvp); $A.free<byte>($A.thaw<byte>(fzp))
end

implement main0 () = let
  val () = _mkdir("dist")
  val () = _mkdir("dist/pwa")

  (* Create a dummy wasm file for testing *)
  val wb = $B.create()
  val () = $B.bput(wb, "dummy wasm")
  val () = _write_file("dist", "app.wasm", wb)

  (* Create PWA with no extra assets *)
  val assets = $A.alloc<byte>(1)
  val () = $P.create_pwa("BATS PWA", "dev.bats.pwa",
    "dist/app.wasm", "app.wasm", "dist/pwa",
    assets, 0, 1)
  val () = $A.free<byte>(assets)

  val () = println! ("PWA generated in dist/pwa/")
in end
