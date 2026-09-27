(* pwa -- PWA and Android app shell generator for bats WASM apps *)
(* Native build tool: writes index.html, bridge.js, service-worker.js, manifest.json to disk *)
(* All JS generation is delegated to the bridge package. *)
(* For Android: writes a Capacitor project around the PWA (create_android) *)

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

(* capacitor.config.json: the app's name and id, and web_dir, the PWA's
   directory relative to the Capacitor project's *)
#pub fn build_capacitor_config {na:nat | na < 256}{ni:nat | ni < 256}{nd:nat | nd < 256}{n:nat | n + 1200 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 1200] $B.builder(m), app_name: string na, app_id: string ni, web_dir: string nd): void

(* package.json of the Capacitor project: Capacitor 8's core, Android
   platform and CLI *)
#pub fn build_capacitor_package {n:nat | n + 600 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 600] $B.builder(m)): void

(* Gradle appended to android/app/build.gradle: the release build is
   signed with android/app/release.jks when it is there, with the
   passwords and alias from the environment (ANDROID_KEYSTORE_PASSWORD,
   ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD), never from a file; the
   version code is ANDROID_VERSION_CODE (1 when unset); the Kotlin
   standard library is pinned to one version, which Capacitor's
   dependencies otherwise pull in twice *)
#pub fn build_android_gradle {n:nat | n + 2000 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 2000] $B.builder(m)): void

(* build-android.sh: builds the Capacitor project it sits in into a
   release AAB and APK (npm install, cap add android, the Gradle above,
   cap sync, gradlew bundleRelease assembleRelease); signed when
   ANDROID_KEYSTORE names a keystore file *)
#pub fn build_android_script {n:nat | n + 3000 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 3000] $B.builder(m)): void

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

(* Writes a Capacitor project in project_dir for the PWA in web_dir
   (relative to project_dir): capacitor.config.json, package.json,
   android-release.gradle and build-android.sh. Running build-android.sh
   (Node, a JDK and the Android SDK needed) builds the Android app. No
   secret is written: signing reads the keystore and its passwords when
   the build runs. *)
#pub fn create_android {na:nat | na < 256}{ni:nat | ni < 256}{nw:nat | nw < 256}{nd:nat | nd < 256}
  (app_name: string na, app_id: string ni, web_dir: string nw, project_dir: string nd): void

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

(* Opens dir/filename for writing (created with mode, truncated) *)
fn _open_out {nd:nat | nd < 256}{nf:nat | nf < 256}
  (dir: string nd, filename: string nf, mode: int): $R.result($F.fd, int) = let
  var pb = $B.create()
  val () = $B.bput(pb, dir)
  val () = $B.put_char(pb, 47)
  val () = $B.bput(pb, filename)
  val () = $B.put_char(pb, 0)
in _open_built(pb, 1 + 64 + 512, mode) end

(* Creates the directory dir (mode 0755); nothing when it exists *)
fn _mkdir {nd:nat | nd < 256} (dir: string nd): void = let
  var mb = $B.create()
  val () = $B.bput(mb, dir)
  val () = $B.put_char(mb, 0)
  val @(ma, _) = $B.to_arr(mb)
  val @(fzm, bvm) = $A.freeze<byte>(ma)
  val () = $R.discard<int><int>($F.file_mkdir(bvm, 524288, 493))
  val () = $A.drop<byte>(fzm, bvm)
in $A.free<byte>($A.thaw<byte>(fzm)) end

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

(* Writes content to dir/filename, created with mode *)
fn _write_mode {nd:nat | nd < 256}{nf:nat | nf < 256}
  (dir: string nd, filename: string nf, content: $B.builder_v, mode: int): void =
  case+ _open_out(dir, filename, mode) of
  | ~$R.ok(fd) => let
      val () = _write_builder(fd, content)
    in $R.discard<int><int>($F.file_close(fd)) end
  | ~$R.err(_) => $B.builder_free(content)

(* Writes content to dir/filename (mode 0644) *)
fn _write_to {nd:nat | nd < 256}{nf:nat | nf < 256}
  (dir: string nd, filename: string nf, content: $B.builder_v): void =
  _write_mode(dir, filename, content, 420)

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
  case+ _open_out(dir, filename, 420) of
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

implement build_capacitor_config (b, app_name, app_id, web_dir) = let
  val () = $B.bput(b, "{\n")
  val () = $B.bput(b, "  \"appId\": \"")
  val () = $B.bput(b, app_id)
  val () = $B.bput(b, "\",\n")
  val () = $B.bput(b, "  \"appName\": \"")
  val () = $B.bput(b, app_name)
  val () = $B.bput(b, "\",\n")
  val () = $B.bput(b, "  \"webDir\": \"")
  val () = $B.bput(b, web_dir)
  val () = $B.bput(b, "\",\n")
  val () = $B.bput(b, "  \"server\": {\n")
  val () = $B.bput(b, "    \"androidScheme\": \"https\"\n")
  val () = $B.bput(b, "  },\n")
  val () = $B.bput(b, "  \"android\": {\n")
  val () = $B.bput(b, "    \"adjustMarginsForEdgeToEdge\": \"auto\"\n")
  val () = $B.bput(b, "  }\n")
  val () = $B.bput(b, "}\n")
in end

implement build_capacitor_package (b) = let
  val () = $B.bput(b, "{\n")
  val () = $B.bput(b, "  \"name\": \"android-shell\",\n")
  val () = $B.bput(b, "  \"private\": true,\n")
  val () = $B.bput(b, "  \"dependencies\": {\n")
  val () = $B.bput(b, "    \"@capacitor/android\": \"^8.1.0\",\n")
  val () = $B.bput(b, "    \"@capacitor/core\": \"^8.1.0\"\n")
  val () = $B.bput(b, "  },\n")
  val () = $B.bput(b, "  \"devDependencies\": {\n")
  val () = $B.bput(b, "    \"@capacitor/cli\": \"^8.1.0\"\n")
  val () = $B.bput(b, "  }\n")
  val () = $B.bput(b, "}\n")
in end

implement build_android_gradle (b) = let
  val () = $B.bput(b, "\n// Appended by the pwa package's build-android.sh\n")
  val () = $B.bput(b, "android {\n")
  val () = $B.bput(b, "    defaultConfig {\n")
  val () = $B.bput(b, "        versionCode Integer.parseInt(System.getenv('ANDROID_VERSION_CODE') ?: '1')\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "    if (file('release.jks').exists()) {\n")
  val () = $B.bput(b, "        signingConfigs {\n")
  val () = $B.bput(b, "            release {\n")
  val () = $B.bput(b, "                storeFile file('release.jks')\n")
  val () = $B.bput(b, "                storePassword System.getenv('ANDROID_KEYSTORE_PASSWORD')\n")
  val () = $B.bput(b, "                keyAlias System.getenv('ANDROID_KEY_ALIAS')\n")
  val () = $B.bput(b, "                keyPassword System.getenv('ANDROID_KEY_PASSWORD')\n")
  val () = $B.bput(b, "            }\n")
  val () = $B.bput(b, "        }\n")
  val () = $B.bput(b, "        buildTypes {\n")
  val () = $B.bput(b, "            release {\n")
  val () = $B.bput(b, "                signingConfig signingConfigs.release\n")
  val () = $B.bput(b, "            }\n")
  val () = $B.bput(b, "        }\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "}\n")
  val () = $B.bput(b, "configurations.all {\n")
  val () = $B.bput(b, "    resolutionStrategy {\n")
  val () = $B.bput(b, "        force 'org.jetbrains.kotlin:kotlin-stdlib:1.8.22'\n")
  val () = $B.bput(b, "        force 'org.jetbrains.kotlin:kotlin-stdlib-jdk7:1.8.22'\n")
  val () = $B.bput(b, "        force 'org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.8.22'\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "}\n")
in end

implement build_android_script (b) = let
  val () = $B.bput(b, "#!/bin/sh\n")
  val () = $B.bput(b, "# Builds this Capacitor project into a release AAB and APK, in\n")
  val () = $B.bput(b, "# android/app/build/outputs/{bundle,apk}/release/. Needs Node, a JDK\n")
  val () = $B.bput(b, "# (21) and the Android SDK (ANDROID_HOME).\n")
  val () = $B.bput(b, "#\n")
  val () = $B.bput(b, "# Signed when ANDROID_KEYSTORE names a keystore file, with\n")
  val () = $B.bput(b, "# ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS and ANDROID_KEY_PASSWORD;\n")
  val () = $B.bput(b, "# unsigned otherwise. ANDROID_VERSION_CODE is the version code (1 when\n")
  val () = $B.bput(b, "# unset); each upload to Google Play needs a higher one.\n")
  val () = $B.bput(b, "set -eu\n")
  val () = $B.bput(b, "cd \"$(dirname \"$0\")\"\n")
  val () = $B.bput(b, "rm -rf android\n")
  val () = $B.bput(b, "npm install\n")
  val () = $B.bput(b, "npx cap add android\n")
  val () = $B.bput(b, "if [ -n \"${ANDROID_KEYSTORE:-}\" ]; then\n")
  val () = $B.bput(b, "  cp \"$ANDROID_KEYSTORE\" android/app/release.jks\n")
  val () = $B.bput(b, "fi\n")
  val () = $B.bput(b, "cat android-release.gradle >> android/app/build.gradle\n")
  val () = $B.bput(b, "npx cap sync android\n")
  val () = $B.bput(b, "cd android\n")
  val () = $B.bput(b, "./gradlew bundleRelease assembleRelease\n")
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
  val () = _mkdir(out_dir)
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

implement create_android (app_name, app_id, web_dir, project_dir) = let
  val () = _mkdir(project_dir)
  var cap_b = $B.create()
  val () = build_capacitor_config(cap_b, app_name, app_id, web_dir)
  val () = _write_to(project_dir, "capacitor.config.json", cap_b)
  var pkg_b = $B.create()
  val () = build_capacitor_package(pkg_b)
  val () = _write_to(project_dir, "package.json", pkg_b)
  var gr_b = $B.create()
  val () = build_android_gradle(gr_b)
  val () = _write_to(project_dir, "android-release.gradle", gr_b)
  var sh_b = $B.create()
  val () = build_android_script(sh_b)
in _write_mode(project_dir, "build-android.sh", sh_b, 493) end
