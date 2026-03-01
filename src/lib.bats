(* pwa -- PWA and APK shell generator for bats WASM apps *)
(* Native build tool: writes index.html, bridge.js, app.js, service-worker.js, manifest.json to disk *)
(* For APK: also writes capacitor.config.json *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use file as F
#use path as P
#use result as R
#use str as S
#use wasm.bats-packages.dev/bridge as BR

(* ============================================================
   Builder-based API (generate file contents into builders)
   ============================================================ *)

#pub fn build_html {na:nat}
  (b: !$B.builder, app_name: string na): void

#pub fn build_bridge_js
  (b: !$B.builder): void

#pub fn build_app_js {nw:nat}
  (b: !$B.builder, wasm_file: string nw): void

#pub fn build_service_worker {nw:nat}
  (b: !$B.builder, wasm_file: string nw): void

#pub fn build_manifest {na:nat}
  (b: !$B.builder, app_name: string na): void

#pub fn build_capacitor_config {na:nat}{ni:nat}{nd:nat}
  (b: !$B.builder, app_name: string na, app_id: string ni, out_dir: string nd): void

(* ============================================================
   High-level API -- write complete PWA/APK to a directory
   ============================================================ *)

(* Create a complete PWA in out_dir.
   Writes index.html, bridge.js, app.js, service-worker.js, manifest.json.
   Copies wasm from wasm_path as wasm_name.
   assets: null-separated source paths to copy into out_dir. *)
#pub fn create_pwa {na:nat}{ni:nat}{nw:nat}{nn:nat}{nd:nat}{la:agz}{nas:pos}
  (app_name: string na, app_id: string ni,
   wasm_path: string nw, wasm_name: string nn,
   out_dir: string nd,
   assets: !$A.arr(byte, la, nas), asset_len: int, asset_max: int nas): void

(* Same as create_pwa plus capacitor.config.json *)
#pub fn create_apk {na:nat}{ni:nat}{nw:nat}{nn:nat}{nd:nat}{la:agz}{nas:pos}
  (app_name: string na, app_id: string ni,
   wasm_path: string nw, wasm_name: string nn,
   out_dir: string nd,
   assets: !$A.arr(byte, la, nas), asset_len: int, asset_max: int nas): void

(* Same as create_apk but generates a signed release AAB.
   Writes release signing config and copies keystore.
   keystore_path: path to release.jks file
   keystore_password: password for the keystore
   key_alias: alias of the signing key
   key_password: password for the key *)
#pub fn create_aab {na:nat}{ni:nat}{nw:nat}{nn:nat}{nd:nat}{la:agz}{nas:pos}{nk:nat}{nkp:nat}{nka:nat}{nkpw:nat}
  (app_name: string na, app_id: string ni,
   wasm_path: string nw, wasm_name: string nn,
   out_dir: string nd,
   assets: !$A.arr(byte, la, nas), asset_len: int, asset_max: int nas,
   keystore_path: string nk, keystore_password: string nkp,
   key_alias: string nka, key_password: string nkpw): void

(* Generate release signing Gradle config *)
#pub fn build_release_signing {nk:nat}{nkp:nat}{nka:nat}{nkpw:nat}
  (b: !$B.builder,
   keystore_path: string nk, keystore_password: string nkp,
   key_alias: string nka, key_password: string nkpw): void

(* ============================================================
   Internal: write builder to dir/filename
   ============================================================ *)

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

(* Copy file from src to dir/filename *)
fn _copy_to {ns:nat}{nd:nat}{nf:nat}
  (src: string ns, dir: string nd, filename: string nf): void = let
  val @(sa, sl) = $S.str_to_borrow(src)
  val @(fzs, bvs) = $A.freeze<byte>(sa)
  val sr = $F.file_open(bvs, $AR.checked_arr_size(sl), 0, 0)
  val () = $A.drop<byte>(fzs, bvs)
  val () = $A.free<byte>($A.thaw<byte>(fzs))
in
  case+ sr of
  | ~$R.ok(sfd) => let
      val buf = $A.alloc<byte>(524288)
      val rr = $F.file_read(sfd, buf, 524288)
      val nb = (case+ rr of | ~$R.ok(n) => n | ~$R.err(_) => 0): int
      val cr = $F.file_close(sfd)
      val () = $R.discard<int><int>(cr)
      val cb = $B.create()
      val @(fzb, bvb) = $A.freeze<byte>(buf)
      fun cp {l:agz}{fuel:nat} .<fuel>.
        (bv: !$A.borrow(byte, l, 524288), i: int, len: int,
         b: !$B.builder, fuel: int fuel): void =
        if fuel <= 0 then () else if i >= len then ()
        else let
          val () = $B.put_byte(b, byte2int0($A.read<byte>(bv, $AR.checked_idx(i, 524288))))
        in cp(bv, i + 1, len, b, fuel - 1) end
      val () = cp(bvb, 0, nb, cb, $AR.checked_nat(nb + 1))
      val () = $A.drop<byte>(fzb, bvb)
      val () = $A.free<byte>($A.thaw<byte>(fzb))
    in _write_to(dir, filename, cb) end
  | ~$R.err(_) => ()
end

(* ============================================================
   Implementations -- builder API
   ============================================================ *)

implement build_html (b, app_name) = let
  val () = $B.bput(b, "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n")
  val () = $B.bput(b, "  <meta charset=\"UTF-8\">\n")
  val () = $B.bput(b, "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, viewport-fit=cover\">\n")
  val () = $B.bput(b, "  <title>")
  val () = $B.bput(b, app_name)
  val () = $B.bput(b, "</title>\n")
  val () = $B.bput(b, "  <meta name=\"theme-color\" content=\"#ffffff\">\n")
  val () = $B.bput(b, "  <link rel=\"manifest\" href=\"manifest.json\">\n")
  val () = $B.bput(b, "  <link rel=\"icon\" href=\"icon-192.png\" type=\"image/png\">\n")
  val () = $B.bput(b, "  <link rel=\"apple-touch-icon\" href=\"icon-192.png\">\n")
  val () = $B.bput(b, "  <style>\n")
  val () = $B.bput(b, "    body { margin: 0; font-family: system-ui, sans-serif; }\n")
  val () = $B.bput(b, "    .loading { display: flex; flex-direction: column; align-items: center;\n")
  val () = $B.bput(b, "      justify-content: center; height: 100vh; }\n")
  val () = $B.bput(b, "    .spinner { width: 40px; height: 40px; border: 4px solid #eee;\n")
  val () = $B.bput(b, "      border-top-color: #333; border-radius: 50%;\n")
  val () = $B.bput(b, "      animation: spin 0.8s linear infinite; }\n")
  val () = $B.bput(b, "    @keyframes spin { to { transform: rotate(360deg); } }\n")
  val () = $B.bput(b, "    .app-name { margin-top: 16px; font-size: 18px; color: #666; }\n")
  val () = $B.bput(b, "  </style>\n")
  val () = $B.bput(b, "</head>\n<body>\n")
  val () = $B.bput(b, "  <div id=\"bats-root\">\n")
  val () = $B.bput(b, "    <div class=\"loading\">\n")
  val () = $B.bput(b, "      <div class=\"spinner\"></div>\n")
  val () = $B.bput(b, "      <div class=\"app-name\">")
  val () = $B.bput(b, app_name)
  val () = $B.bput(b, "</div>\n")
  val () = $B.bput(b, "    </div>\n")
  val () = $B.bput(b, "  </div>\n")
  val () = $B.bput(b, "  <script src=\"bridge.js\"></script>\n")
  val () = $B.bput(b, "  <script src=\"app.js\"></script>\n")
  val () = $B.bput(b, "  <script>\n")
  val () = $B.bput(b, "    if ('serviceWorker' in navigator) {\n")
  val () = $B.bput(b, "      navigator.serviceWorker.register('service-worker.js');\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "  </script>\n")
  val () = $B.bput(b, "</body>\n</html>\n")
in end

implement build_bridge_js (b) =
  $BR.produce_bridge(b)

implement build_app_js (b, wasm_file) = let
  val () = $B.bput(b, "const root = document.getElementById('bats-root');\n")
  val () = $B.bput(b, "const resp = await fetch('")
  val () = $B.bput(b, wasm_file)
  val () = $B.bput(b, "');\n")
  val () = $B.bput(b, "const bytes = await resp.arrayBuffer();\n")
  val () = $B.bput(b, "await loadWASM(bytes, root, {});\n")
in end

implement build_service_worker (b, wasm_file) = let
  val () = $B.bput(b, "const CACHE = 'bats-pwa-v1';\n")
  val () = $B.bput(b, "const SHELL = [\n")
  val () = $B.bput(b, "  './', '")
  val () = $B.bput(b, wasm_file)
  val () = $B.bput(b, "', 'manifest.json',\n")
  val () = $B.bput(b, "];\n\n")
  val () = $B.bput(b, "self.addEventListener('install', e => {\n")
  val () = $B.bput(b, "  self.skipWaiting();\n")
  val () = $B.bput(b, "  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)));\n")
  val () = $B.bput(b, "});\n\n")
  val () = $B.bput(b, "self.addEventListener('activate', e => {\n")
  val () = $B.bput(b, "  e.waitUntil(\n")
  val () = $B.bput(b, "    caches.keys().then(keys =>\n")
  val () = $B.bput(b, "      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))\n")
  val () = $B.bput(b, "    ).then(() => self.clients.claim())\n")
  val () = $B.bput(b, "  );\n")
  val () = $B.bput(b, "});\n\n")
  val () = $B.bput(b, "self.addEventListener('fetch', e => {\n")
  val () = $B.bput(b, "  e.respondWith(caches.match(e.request).then(r => r || fetch(e.request)));\n")
  val () = $B.bput(b, "});\n")
in end

implement build_manifest (b, app_name) = let
  val () = $B.bput(b, "{\n")
  val () = $B.bput(b, "  \"name\": \"")
  val () = $B.bput(b, app_name)
  val () = $B.bput(b, "\",\n")
  val () = $B.bput(b, "  \"short_name\": \"")
  val () = $B.bput(b, app_name)
  val () = $B.bput(b, "\",\n")
  val () = $B.bput(b, "  \"start_url\": \".\",\n")
  val () = $B.bput(b, "  \"display\": \"standalone\",\n")
  val () = $B.bput(b, "  \"background_color\": \"#ffffff\",\n")
  val () = $B.bput(b, "  \"theme_color\": \"#ffffff\",\n")
  val () = $B.bput(b, "  \"icons\": [\n")
  val () = $B.bput(b, "    { \"src\": \"icon-192.png\", \"sizes\": \"192x192\", \"type\": \"image/png\" },\n")
  val () = $B.bput(b, "    { \"src\": \"icon-512.png\", \"sizes\": \"512x512\", \"type\": \"image/png\" }\n")
  val () = $B.bput(b, "  ]\n")
  val () = $B.bput(b, "}\n")
in end

implement build_capacitor_config (b, app_name, app_id, out_dir) = let
  val () = $B.bput(b, "{\n")
  val () = $B.bput(b, "  \"appId\": \"")
  val () = $B.bput(b, app_id)
  val () = $B.bput(b, "\",\n")
  val () = $B.bput(b, "  \"appName\": \"")
  val () = $B.bput(b, app_name)
  val () = $B.bput(b, "\",\n")
  val () = $B.bput(b, "  \"webDir\": \"")
  val () = $B.bput(b, out_dir)
  val () = $B.bput(b, "\",\n")
  val () = $B.bput(b, "  \"server\": {\n")
  val () = $B.bput(b, "    \"androidScheme\": \"https\"\n")
  val () = $B.bput(b, "  }\n")
  val () = $B.bput(b, "}\n")
in end

implement build_release_signing (b, keystore_path, keystore_password, key_alias, key_password) = let
  (* Gradle script applied to android/app/build.gradle for release signing *)
  val () = $B.bput(b, "android {\n")
  val () = $B.bput(b, "    signingConfigs {\n")
  val () = $B.bput(b, "        release {\n")
  val () = $B.bput(b, "            storeFile file('")
  val () = $B.bput(b, keystore_path)
  val () = $B.bput(b, "')\n")
  val () = $B.bput(b, "            storePassword '")
  val () = $B.bput(b, keystore_password)
  val () = $B.bput(b, "'\n")
  val () = $B.bput(b, "            keyAlias '")
  val () = $B.bput(b, key_alias)
  val () = $B.bput(b, "'\n")
  val () = $B.bput(b, "            keyPassword '")
  val () = $B.bput(b, key_password)
  val () = $B.bput(b, "'\n")
  val () = $B.bput(b, "        }\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "    buildTypes {\n")
  val () = $B.bput(b, "        release {\n")
  val () = $B.bput(b, "            signingConfig signingConfigs.release\n")
  val () = $B.bput(b, "        }\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "}\n")
in end

(* ============================================================
   Implementations -- high-level file API
   ============================================================ *)

(* Find basename offset: scan backwards for '/' in a borrow *)
fn _find_basename {l:agz}{n:pos}
  (bv: !$A.borrow(byte, l, n), path_len: int, max: int n): int = let
  fun scan {fuel:nat} .<fuel>.
    (bv: !$A.borrow(byte, l, n), i: int, max: int n, fuel: int fuel): int =
    if fuel <= 0 then 0
    else if i < 0 then 0
    else let
      val c = byte2int0($A.read<byte>(bv, $AR.checked_idx(i, max)))
    in
      if c = 47 then i + 1
      else scan(bv, i - 1, max, fuel - 1)
    end
in scan(bv, path_len - 1, max, $AR.checked_nat(path_len + 1)) end

(* Copy a single asset from assets array at [pos, path_end) to out_dir *)
fn _copy_one_asset {la:agz}{nas:pos}{nd:nat}
  (assets: !$A.arr(byte, la, nas), pos: int, path_end: int,
   asset_max: int nas, out_dir: string nd): void = let
  val path_len = path_end - pos
  (* Build source path into a builder, then freeze for basename scan *)
  val src_b = $B.create()
  fun cp_range {la2:agz}{fuel:nat} .<fuel>.
    (a: !$A.arr(byte, la2, nas), i: int, lim: int, max: int nas,
     b: !$B.builder, fuel: int fuel): void =
    if fuel <= 0 then () else if i >= lim then ()
    else let
      val () = $B.put_byte(b, byte2int0($A.get<byte>(a, $AR.checked_idx(i, max))))
    in cp_range(a, i + 1, lim, max, b, fuel - 1) end
  val () = cp_range(assets, pos, path_end, asset_max, src_b, $AR.checked_nat(path_len + 1))
  val () = $B.put_byte(src_b, 0)
  val @(src_a, src_l) = $B.to_arr(src_b)
  val @(fzs, bvs) = $A.freeze<byte>(src_a)
  (* Find basename in the borrow *)
  val base = _find_basename(bvs, path_len, $AR.checked_arr_size(src_l))
  (* Build dest filename *)
  val dst_b = $B.create()
  fun cp_borrow {l:agz}{fuel:nat} .<fuel>.
    (bv: !$A.borrow(byte, l, 524288), i: int, lim: int,
     b: !$B.builder, fuel: int fuel): void =
    if fuel <= 0 then () else if i >= lim then ()
    else let
      val () = $B.put_byte(b, byte2int0($A.read<byte>(bv, $AR.checked_idx(i, 524288))))
    in cp_borrow(bv, i + 1, lim, b, fuel - 1) end
  val () = cp_borrow(bvs, base, path_len, dst_b, $AR.checked_nat(path_len - base + 1))
  (* Read source file *)
  val sr = $F.file_open(bvs, $AR.checked_arr_size(src_l), 0, 0)
in
  (case+ sr of
  | ~$R.ok(sfd) => let
      val buf = $A.alloc<byte>(524288)
      val rr = $F.file_read(sfd, buf, 524288)
      val nb = (case+ rr of | ~$R.ok(n) => n | ~$R.err(_) => 0): int
      val cr = $F.file_close(sfd)
      val () = $R.discard<int><int>(cr)
      (* Write buf[0..nb) to out_dir/basename *)
      val content_b = $B.create()
      val @(fzb, bvb) = $A.freeze<byte>(buf)
      fun cpb {l:agz}{fuel:nat} .<fuel>.
        (bv: !$A.borrow(byte, l, 524288), i: int, len: int,
         b: !$B.builder, fuel: int fuel): void =
        if fuel <= 0 then () else if i >= len then ()
        else let
          val () = $B.put_byte(b, byte2int0($A.read<byte>(bv, $AR.checked_idx(i, 524288))))
        in cpb(bv, i + 1, len, b, fuel - 1) end
      val () = cpb(bvb, 0, nb, content_b, $AR.checked_nat(nb + 1))
      val () = $A.drop<byte>(fzb, bvb)
      val () = $A.free<byte>($A.thaw<byte>(fzb))
      (* Write content to out_dir/basename *)
      val pb = $B.create()
      val () = $B.bput(pb, out_dir)
      val () = $B.put_byte(pb, 47)
      val () = cp_borrow(bvs, base, path_len, pb, $AR.checked_nat(path_len - base + 1))
      val () = $B.put_byte(pb, 0)
      val @(pa, pl) = $B.to_arr(pb)
      val @(fzp, bvp) = $A.freeze<byte>(pa)
      val @(ca, cl) = $B.to_arr(content_b)
      val @(fzc, bvc) = $A.freeze<byte>(ca)
      val fr = $F.file_open(bvp, $AR.checked_arr_size(pl), 577, 420)
    in
      (case+ fr of
      | ~$R.ok(fd) => let
          val bw = $F.buf_writer_create(fd)
          fun wl {l2:agz}{fuel:nat} .<fuel>.
            (bw: !$F.buf_writer, bv: !$A.borrow(byte, l2, 524288),
             i: int, lim: int, fuel: int fuel): void =
            if fuel <= 0 then ()
            else if i >= lim then ()
            else let
              val b = byte2int0($A.read<byte>(bv, $AR.checked_idx(i, 524288)))
              val wr = $F.buf_write_byte(bw, b)
              val () = $R.discard<int><int>(wr)
            in wl(bw, bv, i + 1, lim, fuel - 1) end
          val () = wl(bw, bvc, 0, cl, $AR.checked_nat(cl + 1))
          val wr = $F.buf_writer_close(bw)
          val () = $R.discard<int><int>(wr)
        in end
      | ~$R.err(_) => ());
      $A.drop<byte>(fzc, bvc); $A.free<byte>($A.thaw<byte>(fzc));
      $A.drop<byte>(fzp, bvp); $A.free<byte>($A.thaw<byte>(fzp))
    end
  | ~$R.err(_) => ());
  $A.drop<byte>(fzs, bvs); $A.free<byte>($A.thaw<byte>(fzs));
  val @(da, dl) = $B.to_arr(dst_b)
  val () = $A.free<byte>(da)
end

(* Iterate through null-separated asset paths and copy each *)
fun _copy_assets {la:agz}{nas:pos}{nd:nat}{fuel:nat} .<fuel>.
  (assets: !$A.arr(byte, la, nas), pos: int, len: int,
   asset_max: int nas, out_dir: string nd, fuel: int fuel): void =
  if fuel <= 0 then ()
  else if pos >= len then ()
  else let
    val path_end = $S.find_null(assets, pos, asset_max, $AR.checked_nat(len - pos + 1))
    val path_len = path_end - pos
  in
    if path_len > 0 then let
      val () = _copy_one_asset(assets, pos, path_end, asset_max, out_dir)
    in _copy_assets(assets, path_end + 1, len, asset_max, out_dir, fuel - 1) end
    else _copy_assets(assets, path_end + 1, len, asset_max, out_dir, fuel - 1)
  end

implement create_pwa (app_name, app_id, wasm_path, wasm_name, out_dir, assets, asset_len, asset_max) = let
  val html_b = $B.create()
  val () = build_html(html_b, app_name)
  val () = _write_to(out_dir, "index.html", html_b)
  val br_b = $B.create()
  val () = build_bridge_js(br_b)
  val () = _write_to(out_dir, "bridge.js", br_b)
  val app_b = $B.create()
  val () = build_app_js(app_b, wasm_name)
  val () = _write_to(out_dir, "app.js", app_b)
  val sw_b = $B.create()
  val () = build_service_worker(sw_b, wasm_name)
  val () = _write_to(out_dir, "service-worker.js", sw_b)
  val mf_b = $B.create()
  val () = build_manifest(mf_b, app_name)
  val () = _write_to(out_dir, "manifest.json", mf_b)
  val () = _copy_to(wasm_path, out_dir, wasm_name)
  val () = _copy_assets(assets, 0, asset_len, asset_max, out_dir, $AR.checked_nat(asset_len + 1))
in end

implement create_apk (app_name, app_id, wasm_path, wasm_name, out_dir, assets, asset_len, asset_max) = let
  val () = create_pwa(app_name, app_id, wasm_path, wasm_name, out_dir, assets, asset_len, asset_max)
  val cap_b = $B.create()
  val () = build_capacitor_config(cap_b, app_name, app_id, out_dir)
  val () = _write_to(out_dir, "capacitor.config.json", cap_b)
in end

implement create_aab (app_name, app_id, wasm_path, wasm_name, out_dir, assets, asset_len, asset_max, keystore_path, keystore_password, key_alias, key_password) = let
  (* Write all APK files (PWA + capacitor.config.json) *)
  val () = create_apk(app_name, app_id, wasm_path, wasm_name, out_dir, assets, asset_len, asset_max)
  (* Write release signing config *)
  val sign_b = $B.create()
  val () = build_release_signing(sign_b, "release.jks", keystore_password, key_alias, key_password)
  val () = _write_to(out_dir, "release-signing.gradle", sign_b)
  (* Copy keystore file *)
  val () = _copy_to(keystore_path, out_dir, "release.jks")
in end
