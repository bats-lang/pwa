(* pwa -- PWA and APK shell generator for bats WASM apps *)
(* Native build tool: writes index.html, bridge.js, service-worker.js, manifest.json to disk *)
(* All JS generation is delegated to the bridge package. *)
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

#pub fn build_html {na:nat | na < 256}{n:nat | n + 1600 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 1600] $B.builder(m), app_name: string na): void

#pub fn build_manifest {na:nat | na < 256}{n:nat | n + 900 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 900] $B.builder(m), app_name: string na): void

#pub fn build_capacitor_config {na:nat | na < 256}{ni:nat | ni < 256}{nd:nat | nd < 256}{n:nat | n + 900 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 900] $B.builder(m), app_name: string na, app_id: string ni, out_dir: string nd): void

(* ============================================================
   High-level API -- write complete PWA/APK to a directory
   ============================================================ *)

(* Create a complete PWA in out_dir.
   Writes index.html, bridge.js, service-worker.js, manifest.json.
   Copies wasm from wasm_path as wasm_name.
   assets[0, asset_len): null-separated source paths to copy into out_dir. *)
#pub fn create_pwa {na:nat | na < 256}{ni:nat | ni < 256}{nw:nat | nw < 256}{nn:nat | nn < 200}{nd:nat | nd < 256}{la:agz}{nas:pos | nas + 257 <= $B.BUILDER_CAP}{k:nat | k <= nas}
  (app_name: string na, app_id: string ni,
   wasm_path: string nw, wasm_name: string nn,
   out_dir: string nd,
   assets: !$A.arr(byte, la, nas), asset_len: int k, asset_max: int nas): void

(* Same as create_pwa plus capacitor.config.json *)
#pub fn create_apk {na:nat | na < 256}{ni:nat | ni < 256}{nw:nat | nw < 256}{nn:nat | nn < 200}{nd:nat | nd < 256}{la:agz}{nas:pos | nas + 257 <= $B.BUILDER_CAP}{k:nat | k <= nas}
  (app_name: string na, app_id: string ni,
   wasm_path: string nw, wasm_name: string nn,
   out_dir: string nd,
   assets: !$A.arr(byte, la, nas), asset_len: int k, asset_max: int nas): void

(* Same as create_apk but generates a signed release AAB.
   Writes release signing config and copies keystore.
   keystore_path: path to release.jks file
   keystore_password: password for the keystore
   key_alias: alias of the signing key
   key_password: password for the key *)
#pub fn create_aab {na:nat | na < 256}{ni:nat | ni < 256}{nw:nat | nw < 256}{nn:nat | nn < 200}{nd:nat | nd < 256}{la:agz}{nas:pos | nas + 257 <= $B.BUILDER_CAP}{k:nat | k <= nas}{nk:nat | nk < 256}{nkp:nat | nkp < 256}{nka:nat | nka < 256}{nkpw:nat | nkpw < 256}
  (app_name: string na, app_id: string ni,
   wasm_path: string nw, wasm_name: string nn,
   out_dir: string nd,
   assets: !$A.arr(byte, la, nas), asset_len: int k, asset_max: int nas,
   keystore_path: string nk, keystore_password: string nkp,
   key_alias: string nka, key_password: string nkpw): void

(* Generate release signing Gradle config *)
#pub fn build_release_signing {nk:nat | nk < 256}{nkp:nat | nkp < 256}{nka:nat | nka < 256}{nkpw:nat | nkpw < 256}{n:nat | n + 1400 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 1400] $B.builder(m),
   keystore_path: string nk, keystore_password: string nkp,
   key_alias: string nka, key_password: string nkpw): void

(* ============================================================
   Internal: paths and files
   ============================================================ *)

(* a[i, e) into b *)
fun _put_range {l:agz}{na:nat}{i,e:nat | i <= e; e <= na}{n:nat | n + e - i <= $B.BUILDER_CAP} .<e - i>.
  (a: !$A.arr(byte, l, na), i: int i, e: int e,
   b: !$B.builder(n) >> $B.builder(n + e - i)): void =
  if i >= e then ()
  else let
    val () = $B.put_byte(b, $AR.low_byte(byte2int0($A.get<byte>(a, i))))
  in _put_range(a, i + 1, e, b) end

(* Opens the NUL-terminated path in b (consumed) with flags and mode *)
fn _open_built (b: $B.builder_v, flags: int, mode: int): $R.result($F.fd, int) = let
  val @(pa, _) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(pa)
  val r = $F.file_open(bv, 524288, flags, mode)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in r end

(* Opens dir/filename for writing (created, truncated) *)
fn _open_out {nd:nat | nd < 256}{nf:nat | nf < 256}
  (dir: string nd, filename: string nf): $R.result($F.fd, int) = let
  var pb = $B.create()
  val () = $B.bput(pb, dir)
  val () = $B.put_char(pb, 47)
  val () = $B.bput(pb, filename)
  val () = $B.put_char(pb, 0)
in _open_built(pb, 1 + 64 + 512, 420) end

(* Writes the bytes of content to f *)
fn _write_builder (f: !$F.fd, content: $B.builder_v): void = let
  val @(ca, cl) = $B.to_arr(content)
  val @(fz, bv) = $A.freeze<byte>(ca)
in
  if cl > 0 then let
    val @(left, right) = $A.borrow_split<byte>(fz, bv, cl)
    val () = $R.discard<int><int>((case+ $F.file_write(f, left, cl) of
      | ~$R.ok(w) => $R.ok(w) | ~$R.err(e) => $R.err(e)): $R.result(int, int))
    val () = $A.drop<byte>(fz, $A.borrow_join<byte>(fz, left, right))
  in $A.free<byte>($A.thaw<byte>(fz)) end
  else let
    val () = $A.drop<byte>(fz, bv)
  in $A.free<byte>($A.thaw<byte>(fz)) end
end

(* Writes content to dir/filename *)
fn _write_to {nd:nat | nd < 256}{nf:nat | nf < 256}
  (dir: string nd, filename: string nf, content: $B.builder_v): void =
  case+ _open_out(dir, filename) of
  | ~$R.ok(fd) => let
      val () = _write_builder(fd, content)
    in $R.discard<int><int>($F.file_close(fd)) end
  | ~$R.err(_) => $B.builder_free(content)

(* Copies the file src (opened by the NUL-terminated path in sb) to f *)
fn _copy_from (sb: $B.builder_v, f: !$F.fd): void =
  case+ _open_built(sb, 0, 0) of
  | ~$R.ok(sfd) => let
      val () = $R.discard<int><int>((case+ $F.fd_copy(sfd, f) of
        | ~$R.ok(c) => $R.ok(c) | ~$R.err(e) => $R.err(e)): $R.result(int, int))
    in $R.discard<int><int>($F.file_close(sfd)) end
  | ~$R.err(_) => ()

(* Copy file from src to dir/filename *)
fn _copy_to {ns:nat | ns < 256}{nd:nat | nd < 256}{nf:nat | nf < 256}
  (src: string ns, dir: string nd, filename: string nf): void =
  case+ _open_out(dir, filename) of
  | ~$R.ok(fd) => let
      var sb = $B.create()
      val () = $B.bput(sb, src)
      val () = $B.put_char(sb, 0)
      val () = _copy_from(sb, fd)
    in $R.discard<int><int>($F.file_close(fd)) end
  | ~$R.err(_) => ()

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
  val () = $B.bput(b, "  <script type=\"module\" src=\"bridge.js\"></script>\n")
  val () = $B.bput(b, "</body>\n</html>\n")
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

(* Start of the last component of the path a[p, e): just after its last
   '/', or p *)
fun _basename {l:agz}{na:nat}{p,i:nat | p <= i; i <= na} .<i - p>.
  (a: !$A.arr(byte, l, na), p: int p, i: int i): [b:nat | p <= b; b <= i] int b =
  if i <= p then p
  else if byte2int0($A.get<byte>(a, i - 1)) = 47 then i
  else _basename(a, p, i - 1)

(* End of the path that starts at p: the first NUL at or after p, or k *)
fun _path_end {l:agz}{na:nat}{i,k:nat | i <= k; k <= na} .<k - i>.
  (a: !$A.arr(byte, l, na), i: int i, k: int k): [e:nat | i <= e; e <= k] int e =
  if i >= k then k
  else if byte2int0($A.get<byte>(a, i)) = 0 then i
  else _path_end(a, i + 1, k)

(* Copies the file at the path assets[p, e) to out_dir/<its basename> *)
fn _copy_one_asset {la:agz}{nas:nat | nas + 257 <= $B.BUILDER_CAP}{p,e:nat | p <= e; e <= nas}{nd:nat | nd < 256}
  (assets: !$A.arr(byte, la, nas), p: int p, e: int e, out_dir: string nd): void = let
  val base = _basename(assets, p, e)
  var db = $B.create()
  val () = $B.bput(db, out_dir)
  val () = $B.put_char(db, 47)
  val () = _put_range(assets, base, e, db)
  val () = $B.put_char(db, 0)
in
  case+ _open_built(db, 1 + 64 + 512, 420) of
  | ~$R.ok(fd) => let
      var sb = $B.create()
      val () = _put_range(assets, p, e, sb)
      val () = $B.put_char(sb, 0)
      val () = _copy_from(sb, fd)
    in $R.discard<int><int>($F.file_close(fd)) end
  | ~$R.err(_) => ()
end

(* Copies each non-empty path of the NUL-separated list assets[p, k) *)
fun _copy_assets {la:agz}{nas:nat | nas + 257 <= $B.BUILDER_CAP}{p,k:nat | p <= k; k <= nas}{nd:nat | nd < 256} .<k - p>.
  (assets: !$A.arr(byte, la, nas), p: int p, k: int k, out_dir: string nd): void =
  if p >= k then ()
  else let
    val e = _path_end(assets, p, k)
    val () = (if e > p then _copy_one_asset(assets, p, e, out_dir) else ())
  in
    if e >= k then () else _copy_assets(assets, e + 1, k, out_dir)
  end

implement create_pwa (app_name, app_id, wasm_path, wasm_name, out_dir, assets, asset_len, asset_max) = let
  var mb = $B.create()
  val () = $B.bput(mb, out_dir)
  val () = $B.put_char(mb, 0)
  val @(ma, _) = $B.to_arr(mb)
  val @(fzm, bvm) = $A.freeze<byte>(ma)
  val mr = $F.file_mkdir(bvm, 524288, 493)
  val () = $R.discard<int><int>(mr)
  val () = $A.drop<byte>(fzm, bvm)
  val () = $A.free<byte>($A.thaw<byte>(fzm))
  var html_b = $B.create()
  val () = build_html(html_b, app_name)
  val () = _write_to(out_dir, "index.html", html_b)
  var br_b = $B.create()
  val () = $BR.produce_bridge_app(br_b, wasm_name, "bats-root")
  val () = _write_to(out_dir, "bridge.js", br_b)
  var sw_b = $B.create()
  val () = $BR.produce_service_worker(sw_b, wasm_name)
  val () = _write_to(out_dir, "service-worker.js", sw_b)
  var mf_b = $B.create()
  val () = build_manifest(mf_b, app_name)
  val () = _write_to(out_dir, "manifest.json", mf_b)
  val () = _copy_to(wasm_path, out_dir, wasm_name)
  val () = _copy_assets(assets, 0, asset_len, out_dir)
in end

implement create_apk (app_name, app_id, wasm_path, wasm_name, out_dir, assets, asset_len, asset_max) = let
  val () = create_pwa(app_name, app_id, wasm_path, wasm_name, out_dir, assets, asset_len, asset_max)
  var cap_b = $B.create()
  val () = build_capacitor_config(cap_b, app_name, app_id, out_dir)
  val () = _write_to(out_dir, "capacitor.config.json", cap_b)
in end

implement create_aab (app_name, app_id, wasm_path, wasm_name, out_dir, assets, asset_len, asset_max, keystore_path, keystore_password, key_alias, key_password) = let
  (* Write all APK files (PWA + capacitor.config.json) *)
  val () = create_apk(app_name, app_id, wasm_path, wasm_name, out_dir, assets, asset_len, asset_max)
  (* Write release signing config *)
  var sign_b = $B.create()
  val () = build_release_signing(sign_b, "release.jks", keystore_password, key_alias, key_password)
  val () = _write_to(out_dir, "release-signing.gradle", sign_b)
  (* Copy keystore file *)
  val () = _copy_to(keystore_path, out_dir, "release.jks")
in end
