(* pwa -- generate PWA shell files into dist/pwa/ *)
#target native

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use file as F
#use process as PR
#use pwa as P
#use result as R

(* Copy string into builder *)
fun bput_loop {sn:nat}{fuel:nat} .<fuel>.
  (b: !$B.builder, s: string sn, slen: int sn, i: int, fuel: int fuel): void =
  if fuel <= 0 then ()
  else let val ii = g1ofg0(i) in
    if ii >= 0 then
      if ii < slen then let
        val c = char2int0(string_get_at(s, ii))
        val () = $B.put_byte(b, c)
      in bput_loop(b, s, slen, i + 1, fuel - 1) end
      else ()
    else ()
  end

fn bput {sn:nat} (b: !$B.builder, s: string sn): void = let
  val slen_sz = string1_length(s)
  val slen = g1u2i(slen_sz)
in bput_loop(b, s, slen, 0, $AR.checked_nat(g0ofg1(slen) + 1)) end

(* Write builder to file via buf_writer *)
fun wbw {l:agz}{fuel:nat} .<fuel>.
  (bw: !$F.buf_writer, bv: !$A.borrow(byte, l, 524288),
   i: int, lim: int, fuel: int fuel): void =
  if fuel <= 0 then ()
  else if i >= lim then ()
  else let
    val p = g1ofg0(i)
  in
    if p >= 0 then
      if p < 524288 then let
        val b = byte2int0($A.read<byte>(bv, p))
        val wr = $F.buf_write_byte(bw, b)
        val () = $R.discard<int><int>(wr)
      in wbw(bw, bv, i + 1, lim, fuel - 1) end
      else ()
    else ()
  end

fn write_builder_to_file {sn:nat}
  (path: string sn, content: $B.builder): void = let
  val pb = $B.create()
  val () = bput(pb, path)
  val () = $B.put_byte(pb, 0)
  val @(pa, _) = $B.to_arr(pb)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  val fd_r = $F.file_open(bv_p, 524288, 577, 420)
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
  val @(ca, clen) = $B.to_arr(content)
in
  case+ fd_r of
  | ~$R.ok(fd) => let
      val bw = $F.buf_writer_create(fd)
      val @(fz_c, bv_c) = $A.freeze<byte>(ca)
      val () = wbw(bw, bv_c, 0, clen, $AR.checked_nat(clen + 1))
      val () = $A.drop<byte>(fz_c, bv_c)
      val () = $A.free<byte>($A.thaw<byte>(fz_c))
      val cr = $F.buf_writer_close(bw)
      val () = $R.discard<int><int>(cr)
    in end
  | ~$R.err(_) => let
      val () = $A.free<byte>(ca)
    in println! ("error: cannot write ", path) end
end

fn run_cmd {sn:nat} (cmd: string sn): void = let
  val cb = $B.create()
  val () = bput(cb, cmd)
  val @(ca, clen) = $B.to_arr(cb)
  val @(fz_c, bv_c) = $A.freeze<byte>(ca)
  (* /bin/sh -c <cmd> *)
  val sh = $A.alloc<byte>(7)
  val () = $A.write_byte(sh, 0, 47)
  val () = $A.write_byte(sh, 1, 98)
  val () = $A.write_byte(sh, 2, 105)
  val () = $A.write_byte(sh, 3, 110)
  val () = $A.write_byte(sh, 4, 47)
  val () = $A.write_byte(sh, 5, 115)
  val () = $A.write_byte(sh, 6, 104)
  val @(fz_sh, bv_sh) = $A.freeze<byte>(sh)
  val argv = $B.create()
  val () = $B.put_byte(argv, 115) val () = $B.put_byte(argv, 104) val () = $B.put_byte(argv, 0)
  val () = $B.put_byte(argv, 45) val () = $B.put_byte(argv, 99) val () = $B.put_byte(argv, 0)
  fun copy_cmd {l2:agz}{fuel:nat} .<fuel>.
    (bv2: !$A.borrow(byte, l2, 524288), i: int, len: int,
     dst: !$B.builder, fuel: int fuel): void =
    if fuel <= 0 then ()
    else if i >= len then ()
    else let val p = g1ofg0(i) in
      if p >= 0 then if p < 524288 then let
        val b = byte2int0($A.read<byte>(bv2, p))
        val () = $B.put_byte(dst, b)
      in copy_cmd(bv2, i + 1, len, dst, fuel - 1) end else () else ()
    end
  val () = copy_cmd(bv_c, 0, clen, argv, $AR.checked_nat(clen + 1))
  val () = $B.put_byte(argv, 0)
  val @(aa, _) = $B.to_arr(argv)
  val @(fz_a, bv_a) = $A.freeze<byte>(aa)
  val envp = $A.alloc<byte>(1)
  val () = $A.write_byte(envp, 0, 0)
  val @(fz_e, bv_e) = $A.freeze<byte>(envp)
  val sr = $PR.spawn(bv_sh, 7, bv_a, 3, bv_e, 0,
    $PR.dev_null(), $PR.dev_null(), $PR.dev_null())
  val () = $A.drop<byte>(fz_sh, bv_sh)
  val () = $A.free<byte>($A.thaw<byte>(fz_sh))
  val () = $A.drop<byte>(fz_a, bv_a)
  val () = $A.free<byte>($A.thaw<byte>(fz_a))
  val () = $A.drop<byte>(fz_e, bv_e)
  val () = $A.free<byte>($A.thaw<byte>(fz_e))
  val () = $A.drop<byte>(fz_c, bv_c)
  val () = $A.free<byte>($A.thaw<byte>(fz_c))
in
  case+ sr of
  | ~$R.ok(sp) => let
      val+ ~$PR.spawn_pipes_mk(child, sin_p, sout_p, serr_p) = sp
      val () = $PR.pipe_end_close(sin_p)
      val () = $PR.pipe_end_close(sout_p)
      val () = $PR.pipe_end_close(serr_p)
      val wr = $PR.child_wait(child)
      val () = $R.discard<int><int>(wr)
    in end
  | ~$R.err(_) => ()
end

implement main0 () = let
  val () = run_cmd("mkdir -p dist/pwa")

  val html_b = $B.create()
  val () = $P.build_html(html_b, "BATS PWA", "output.wasm")
  val () = write_builder_to_file("dist/pwa/index.html", html_b)

  val sw_b = $B.create()
  val () = $P.build_service_worker(sw_b, "output.wasm")
  val () = write_builder_to_file("dist/pwa/service-worker.js", sw_b)

  val mf_b = $B.create()
  val () = $P.build_manifest(mf_b, "BATS PWA")
  val () = write_builder_to_file("dist/pwa/manifest.json", mf_b)

  val () = run_cmd("cp dist/debug/output.wasm dist/pwa/ 2>/dev/null || cp dist/release/output.wasm dist/pwa/ 2>/dev/null")
  val () = println! ("PWA generated in dist/pwa/")
in end
