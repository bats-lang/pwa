(* pwa -- PWA and Android app shell generator for bats WASM apps *)
(* Native build tool: writes index.html, bridge.js, service-worker.js, manifest.json to disk *)
(* All JS generation is delegated to the bridge package: the page holds
   bridge.js and nothing else, and the service worker is bridge's. *)
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

(* index.html: the app's name while it loads, and bridge.js, which loads
   the app; no script of its own *)
#pub fn build_html {na:nat | na < 256}{n:nat | n + 2000 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 2000] $B.builder(m), app_name: string na): void

#pub fn build_manifest {na:nat | na < 256}{n:nat | n + 900 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 900] $B.builder(m), app_name: string na): void

(* The manifest of an app that opens files of type mime (extension ext,
   with its dot): as build_manifest, and the system opens those files
   with the installed app (file_handlers: bridge reads launchQueue and
   hands them to the app's listen_external_files) and
   shares them with it (share_target: a POST bridge's service worker
   keeps, and bridge hands to the app's listen_external_files) *)
#pub fn build_manifest_opening {na:nat | na < 256}{nm,ne:nat | nm < 256; ne < 256}{n:nat | n + 2600 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 2600] $B.builder(m), app_name: string na, mime: string nm, ext: string ne): void

(* capacitor.config.json: the app's name and id, and web_dir, the PWA's
   directory relative to the Capacitor project's *)
#pub fn build_capacitor_config {na:nat | na < 256}{ni:nat | ni < 256}{nd:nat | nd < 256}{n:nat | n + 1200 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 1200] $B.builder(m), app_name: string na, app_id: string ni, web_dir: string nd): void

(* package.json of the Capacitor project: Capacitor 8's core, Android
   platform and CLI, and the plugins bridge's atoms use, from bridge's
   table of them (bridge#119), so the app has every plugin an atom may
   call and pwa names none itself *)
#pub fn build_capacitor_package {n:nat | n + 900 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 900] $B.builder(m)): void

(* Gradle appended to android/app/build.gradle: the release build is
   signed with android/app/release.jks when it is there, with the
   passwords and alias from the environment (ANDROID_KEYSTORE_PASSWORD,
   ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD), never from a file; the
   version code is ANDROID_VERSION_CODE (1 when unset); the Kotlin
   standard library is pinned to one version, which Capacitor's
   dependencies otherwise pull in twice: the one bridge's plugins need
   (produce_kotlin_version, the newest any is compiled with; an older
   one crashed the app at a plugin's first call, quire#223) *)
#pub fn build_android_gradle {n:nat | n + 2000 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 2000] $B.builder(m)): void

(* build-android.sh: builds the Capacitor project it sits in into a
   release AAB and APK (pnpm install, cap add android, the app's own
   MainActivity, its intent filters and launcher icon, the Gradle above,
   cap sync, gradlew bundleRelease assembleRelease); signed when
   ANDROID_KEYSTORE names a keystore file. The launcher icon is the
   PWA's icon-512.png in web_dir (relative to the project), when there
   is one. *)
#pub fn build_android_script {nw:nat | nw < 256}{n:nat | n + 4000 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 4000] $B.builder(m), web_dir: string nw): void

(* MainActivity.java for app app_id: the Capacitor activity, which hands
   each file the app is opened with (VIEW) or shared (SEND,
   SEND_MULTIPLE) to the page. The file is copied to the app's cache,
   and the page is given its local URL and name through
   bridge's batsNative.deliverFile (the bridge's external files), once the page has
   it. Each intent is handed over once: Capacitor's BridgeActivity.onCreate
   hands the launch intent to onNewIntent (its load()), which is its one
   hand-over, and an intent handed over before (the activity recreated,
   or started again from the recent apps) is not handed over again
   (bats-lang/quire#247), to the page or to Capacitor's plugins: an
   address the app was opened at (the App plugin's appUrlOpen) reaches
   the page once too. At each window insets dispatch to the web view,
   whether the status bar and the navigation bar are shown (the window's
   own insets, ViewCompat.getRootWindowInsets, isVisible of each: from
   API 30 Android's visibility; below it androidx's reading of the
   window's insets) goes to bridge's batsNative.systemBars, the latest
   once the page has it; the web view takes the insets as it would
   without the listener (bats-lang/quire#314). *)
#pub fn build_main_activity {ni:nat | ni < 256}{n:nat | n + 11500 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 11500] $B.builder(m), app_id: string ni): void

(* The intent filters build-android.sh adds to MainActivity: it opens
   (VIEW) and is shared (SEND, SEND_MULTIPLE) files of type mime *)
#pub fn build_intent_filters {nm:nat | nm < 256}{n:nat | n + 1500 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 1500] $B.builder(m), mime: string nm): void

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

(* As create_pwa, for an app that opens files of type mime (extension
   ext, with its dot): the installed app is offered them by the system
   (build_manifest_opening), and bridge's service worker keeps those
   shared with it, for bridge to hand them to the app *)
#pub fn create_pwa_opening {na:nat | na < 256}{ni:nat | ni < 256}{nw:nat | nw < 256}{nn:nat | nn < 200}{nd:nat | nd < 256}{la:agz}{nas:pos | nas + 257 <= $B.BUILDER_CAP}{k:nat | k <= nas}{nm,ne:nat | nm < 256; ne < 256}
  (app_name: string na, app_id: string ni,
   wasm_path: string nw, wasm_name: string nn,
   out_dir: string nd,
   assets: !$A.arr(byte, la, nas), asset_len: int k, asset_max: int nas,
   mime: string nm, ext: string ne): void

(* smoke-test.sh, for app app_id: on a running emulator or device
   (adb), installs the APK given as its first argument (signing it with
   a throwaway key when it is unsigned), launches it, and waits up to
   two minutes for the text given as its second argument to be on the
   screen; writes screenshot.png, ui.xml and logcat.txt to the directory
   given as its third. With a fourth, fifth and sixth (a file, its type
   and a text, on an emulator where adb can be root), it then starts the
   app anew with the file (VIEW) and waits for that text too, turns and
   recreates the activity, and opens and shares the file with it while it
   is open (VIEW, SEND): the activity must hand the file to the page once
   for each intent, and for none as it is turned or recreated
   (bats-lang/quire#247). Fails when a text never shows, a file is not
   handed over once, the app crashes, or the page logs an error to the
   console. *)
#pub fn build_smoke_test_script {ni:nat | ni < 256}{n:nat | n + 12000 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 12000] $B.builder(m), app_id: string ni): void

(* Writes a Capacitor project in project_dir for the PWA in web_dir
   (relative to project_dir): capacitor.config.json, package.json,
   android-release.gradle, MainActivity.java, intent-filters.xml,
   backup-rules.xml and data-extraction-rules.xml (Auto Backup keeps
   bridge's backed-up files only), build-android.sh and smoke-test.sh. Running build-android.sh (Node,
   a JDK and the Android SDK needed) builds the Android app, which opens
   and is shared files of type mime. No secret is written: signing
   reads the keystore and its passwords when the build runs. *)
#pub fn create_android {na:nat | na < 256}{ni:nat | ni < 256}{nw:nat | nw < 256}{nd:nat | nd < 256}{nm:nat | nm < 256}
  (app_name: string na, app_id: string ni, web_dir: string nw, project_dir: string nd, mime: string nm): void

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

(* Opens the NUL-terminated path in b (consumed) for access, as opening
   says, with mode *)
fn _open_built (b: $B.builder_v, access: $F.access, opening: $F.opening, mode: int): $R.result($F.fd, $F.io_error) = let
  val @(pa, _) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(pa)
  val r = $F.file_open(bv, 524288, access, opening, mode)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in r end

(* Opens dir/filename for writing (created with mode, truncated) *)
fn _open_out {nd:nat | nd < 256}{nf:nat | nf < 256}
  (dir: string nd, filename: string nf, mode: int): $R.result($F.fd, $F.io_error) = let
  var pb = $B.create()
  val () = $B.bput(pb, dir)
  val () = $B.put_char(pb, 47)
  val () = $B.bput(pb, filename)
  val () = $B.put_char(pb, 0)
in _open_built(pb, $F.WriteOnly(), $F.CreateOrTruncate(), mode) end

(* Creates the directory dir (mode 0755); nothing when it exists *)
fn _mkdir {nd:nat | nd < 256} (dir: string nd): void = let
  var mb = $B.create()
  val () = $B.bput(mb, dir)
  val () = $B.put_char(mb, 0)
  val @(ma, _) = $B.to_arr(mb)
  val @(fzm, bvm) = $A.freeze<byte>(ma)
  val () = $R.discard<int><$F.io_error>($F.file_mkdir(bvm, 524288, 493))
  val () = $A.drop<byte>(fzm, bvm)
in $A.free<byte>($A.thaw<byte>(fzm)) end

(* Writes the bytes of content to f *)
fn _write_builder (f: !$F.fd, content: $B.builder_v): void = let
  val @(ca, cl) = $B.to_arr(content)
  val @(fz, bv) = $A.freeze<byte>(ca)
in
  if cl > 0 then let
    val @(left, right) = $A.borrow_split<byte>(fz, bv, cl)
    val () = $R.discard<int><$F.io_error>((case+ $F.file_write(f, left, cl) of
      | ~$R.ok(w) => $R.ok(w) | ~$R.err(e) => $R.err(e)): $R.result(int, $F.io_error))
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
    in $R.discard<int><$F.io_error>($F.file_close(fd)) end
  | ~$R.err(_) => $B.builder_free(content)

(* Writes content to dir/filename (mode 0644) *)
fn _write_to {nd:nat | nd < 256}{nf:nat | nf < 256}
  (dir: string nd, filename: string nf, content: $B.builder_v): void =
  _write_mode(dir, filename, content, 420)

(* Copies the file src (opened by the NUL-terminated path in sb) to f *)
fn _copy_from (sb: $B.builder_v, f: !$F.fd): void =
  case+ _open_built(sb, $F.ReadOnly(), $F.OpenExisting(), 0) of
  | ~$R.ok(sfd) => let
      val () = $R.discard<int><$F.io_error>((case+ $F.fd_copy(sfd, f) of
        | ~$R.ok(c) => $R.ok(c) | ~$R.err(e) => $R.err(e)): $R.result(int, $F.io_error))
    in $R.discard<int><$F.io_error>($F.file_close(sfd)) end
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
    in $R.discard<int><$F.io_error>($F.file_close(fd)) end
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

implement build_manifest_opening (b, app_name, mime, ext) = let
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
  val () = $B.bput(b, "  ],\n")
  val () = $B.bput(b, "  \"file_handlers\": [{ \"action\": \"./\", \"accept\": { \"")
  val () = $B.bput(b, mime)
  val () = $B.bput(b, "\": [\"")
  val () = $B.bput(b, ext)
  val () = $B.bput(b, "\"] } }],\n")
  val () = $B.bput(b, "  \"share_target\": { \"action\": \"./share-target\", \"method\": \"POST\", \"enctype\": \"multipart/form-data\",\n")
  val () = $B.bput(b, "    \"params\": { \"files\": [{ \"name\": \"file\", \"accept\": [\"")
  val () = $B.bput(b, mime)
  val () = $B.bput(b, "\", \"")
  val () = $B.bput(b, ext)
  val () = $B.bput(b, "\"] }] } }\n")
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
  (* the page's console in logcat in a release build too, where the
     smoke test looks for its errors *)
  val () = $B.bput(b, "  \"loggingBehavior\": \"production\",\n")
  val () = $B.bput(b, "  \"android\": {\n")
  val () = $B.bput(b, "    \"adjustMarginsForEdgeToEdge\": \"auto\"\n")
  val () = $B.bput(b, "  },\n")
  (* The page lays itself out with the env() safe-area insets, which the
     WebView gives it: SystemBars need not inject its own CSS variables
     (which it tries before the page has a document, an error on every
     start) *)
  val () = $B.bput(b, "  \"plugins\": {\n")
  val () = $B.bput(b, "    \"SystemBars\": {\n")
  val () = $B.bput(b, "      \"insetsHandling\": \"native\"\n")
  val () = $B.bput(b, "    },\n")
  (* fetch and XMLHttpRequest to another origin go through the
     platform's HTTP, which CORS does not restrict: an app can read a
     server (an OPDS catalogue, say) that a browser page cannot. The
     app's own files (relative URLs) still load through the WebView *)
  val () = $B.bput(b, "    \"CapacitorHttp\": {\n")
  val () = $B.bput(b, "      \"enabled\": true\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "  }\n")
  val () = $B.bput(b, "}\n")
in end

implement build_capacitor_package (b) = let
  val () = $B.bput(b, "{\n")
  val () = $B.bput(b, "  \"name\": \"android-shell\",\n")
  val () = $B.bput(b, "  \"private\": true,\n")
  val () = $B.bput(b, "  \"dependencies\": {\n")
  val () = $B.bput(b, "    \"@capacitor/android\": \"^8.1.0\",\n")
  val () = $B.bput(b, "    \"@capacitor/core\": \"^8.1.0\",\n")
  val () = $BR.produce_plugin_dependencies(b, "    ")
  val () = $B.bput(b, "\n  },\n")
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
  val () = $B.bput(b, "        force 'org.jetbrains.kotlin:kotlin-stdlib:")
  val () = $B.bput(b, $BR.produce_kotlin_version())
  val () = $B.bput(b, "'\n")
  val () = $B.bput(b, "        force 'org.jetbrains.kotlin:kotlin-stdlib-jdk7:")
  val () = $B.bput(b, $BR.produce_kotlin_version())
  val () = $B.bput(b, "'\n")
  val () = $B.bput(b, "        force 'org.jetbrains.kotlin:kotlin-stdlib-jdk8:")
  val () = $B.bput(b, $BR.produce_kotlin_version())
  val () = $B.bput(b, "'\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "}\n")
in end

implement build_android_script (b, web_dir) = let
  val () = $B.bput(b, "#!/bin/sh\n")
  val () = $B.bput(b, "# Builds this Capacitor project into a release AAB and APK, in\n")
  val () = $B.bput(b, "# android/app/build/outputs/{bundle,apk}/release/. Needs Node with\n")
  val () = $B.bput(b, "# corepack (22 or 24; Node 25 ships none), a JDK (21) and the Android\n")
  val () = $B.bput(b, "# SDK (ANDROID_HOME).\n")
  val () = $B.bput(b, "#\n")
  val () = $B.bput(b, "# Signed when ANDROID_KEYSTORE names a keystore file, with\n")
  val () = $B.bput(b, "# ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS and ANDROID_KEY_PASSWORD;\n")
  val () = $B.bput(b, "# unsigned otherwise. ANDROID_VERSION_CODE is the version code (1 when\n")
  val () = $B.bput(b, "# unset); each upload to Google Play needs a higher one.\n")
  val () = $B.bput(b, "set -eu\n")
  val () = $B.bput(b, "cd \"$(dirname \"$0\")\"\n")
  val () = $B.bput(b, "rm -rf android\n")
  val () = $B.bput(b, "# pnpm, at one version, through the corepack Node ships (quire#321: it\n")
  val () = $B.bput(b, "# installs a package from a subfolder of a git repository, which npm\n")
  val () = $B.bput(b, "# cannot); node_modules flat, where Capacitor's Gradle files look for\n")
  val () = $B.bput(b, "# the plugins (pnpm reads nodeLinker from pnpm-workspace.yaml, not\n")
  val () = $B.bput(b, "# from .npmrc)\n")
  val () = $B.bput(b, "export COREPACK_ENABLE_DOWNLOAD_PROMPT=0\n")
  val () = $B.bput(b, "pnpm=\"corepack pnpm@12.9.1\"\n")
  val () = $B.bput(b, "printf 'nodeLinker: hoisted\\n' > pnpm-workspace.yaml\n")
  val () = $B.bput(b, "$pnpm install\n")
  val () = $B.bput(b, "$pnpm exec cap add android\n")
  val () = $B.bput(b, "if [ -n \"${ANDROID_KEYSTORE:-}\" ]; then\n")
  val () = $B.bput(b, "  cp \"$ANDROID_KEYSTORE\" android/app/release.jks\n")
  val () = $B.bput(b, "fi\n")
  val () = $B.bput(b, "# the app's activity, which hands the files it is opened with and\n")
  val () = $B.bput(b, "# shared to the page, and its intent filters\n")
  val () = $B.bput(b, "cp MainActivity.java \"$(find android/app/src/main/java -name MainActivity.java)\"\n")
  val () = $B.bput(b, "m=android/app/src/main/AndroidManifest.xml\n")
  val () = $B.bput(b, "awk 'FNR==NR { f = f $0 \"\\n\"; next } /<\\/activity>/ && !d { printf \"%s\", f; d = 1 } { print }' intent-filters.xml \"$m\" > \"$m.new\"\n")
  val () = $B.bput(b, "mv \"$m.new\" \"$m\"\n")
  val () = $B.bput(b, "# Auto Backup keeps the directory of bridge's backed-up files and\n")
  val () = $B.bput(b, "# nothing else of the app's (the WebView's data, the books, stay out)\n")
  val () = $B.bput(b, "mkdir -p android/app/src/main/res/xml\n")
  val () = $B.bput(b, "cp backup-rules.xml android/app/src/main/res/xml/backup_rules.xml\n")
  val () = $B.bput(b, "cp data-extraction-rules.xml android/app/src/main/res/xml/data_extraction_rules.xml\n")
  val () = $B.bput(b, "awk '/<application/ && !d { sub(/<application/, \"<application android:fullBackupContent=\\\"@xml/backup_rules\\\" android:dataExtractionRules=\\\"@xml/data_extraction_rules\\\"\"); d = 1 } { print }' \"$m\" > \"$m.new\"\n")
  val () = $B.bput(b, "mv \"$m.new\" \"$m\"\n")
  val () = $B.bput(b, "# the launcher icon: the PWA's\n")
  val () = $B.bput(b, "icon=\"")
  val () = $B.bput(b, web_dir)
  val () = $B.bput(b, "/icon-512.png\"\n")
  val () = $B.bput(b, "if [ -f \"$icon\" ]; then\n")
  val () = $B.bput(b, "  for d in android/app/src/main/res/mipmap-*dpi; do\n")
  val () = $B.bput(b, "    for f in ic_launcher ic_launcher_round ic_launcher_foreground; do\n")
  val () = $B.bput(b, "      cp \"$icon\" \"$d/$f.png\"\n")
  val () = $B.bput(b, "    done\n")
  val () = $B.bput(b, "  done\n")
  val () = $B.bput(b, "  rm -rf android/app/src/main/res/mipmap-anydpi-v26\n")
  val () = $B.bput(b, "fi\n")
  val () = $B.bput(b, "cat android-release.gradle >> android/app/build.gradle\n")
  val () = $B.bput(b, "$pnpm exec cap sync android\n")
  val () = $B.bput(b, "cd android\n")
  val () = $B.bput(b, "./gradlew bundleRelease assembleRelease\n")
in end

implement build_main_activity (b, app_id) = let
  val () = $B.bput(b, "package ")
  val () = $B.bput(b, app_id)
  val () = $B.bput(b, ";\n")
  val () = $B.bput(b, "\n")
  val () = $B.bput(b, "import android.content.Intent;\n")
  val () = $B.bput(b, "import android.database.Cursor;\n")
  val () = $B.bput(b, "import android.media.AudioManager;\n")
  val () = $B.bput(b, "import android.net.Uri;\n")
  val () = $B.bput(b, "import android.os.Bundle;\n")
  val () = $B.bput(b, "import android.os.Handler;\n")
  val () = $B.bput(b, "import android.os.Looper;\n")
  val () = $B.bput(b, "import android.provider.OpenableColumns;\n")
  val () = $B.bput(b, "import android.util.Log;\n")
  val () = $B.bput(b, "import android.view.KeyEvent;\n")
  val () = $B.bput(b, "import androidx.core.view.ViewCompat;\n")
  val () = $B.bput(b, "import androidx.core.view.WindowInsetsCompat;\n")
  val () = $B.bput(b, "import com.getcapacitor.BridgeActivity;\n")
  val () = $B.bput(b, "import java.io.File;\n")
  val () = $B.bput(b, "import java.io.FileOutputStream;\n")
  val () = $B.bput(b, "import java.io.InputStream;\n")
  val () = $B.bput(b, "import java.io.OutputStream;\n")
  val () = $B.bput(b, "import java.util.ArrayList;\n")
  val () = $B.bput(b, "import org.json.JSONObject;\n")
  val () = $B.bput(b, "\n")
  val () = $B.bput(b, "// Written by the pwa package. Hands each file the app is opened with\n")
  val () = $B.bput(b, "// (VIEW) or shared (SEND, SEND_MULTIPLE) to the page: the file is\n")
  val () = $B.bput(b, "// copied to the cache, and the page fetches it from its local URL.\n")
  val () = $B.bput(b, "// The volume keys, which a WebView never gives the page, are offered\n")
  val () = $B.bput(b, "// to it as a browser's keydown; one the page takes is the page's.\n")
  val () = $B.bput(b, "// Whether each system bar is shown is handed to the page at each window\n")
  val () = $B.bput(b, "// insets dispatch, which a WebView never tells the page either.\n")
  val () = $B.bput(b, "public class MainActivity extends BridgeActivity {\n")
  val () = $B.bput(b, "    private static final String TAG = \"BatsFiles\";\n")
  val () = $B.bput(b, "    private final Handler handler = new Handler(Looper.getMainLooper());\n")
  val () = $B.bput(b, "\n")
  val () = $B.bput(b, "    // Whether the intent BridgeActivity.onCreate's load() hands to\n")
  val () = $B.bput(b, "    // onNewIntent was handed over before: the activity is recreated (a\n")
  val () = $B.bput(b, "    // configuration change it does not take itself, or its process\n")
  val () = $B.bput(b, "    // stopped in the background), or started from the recent apps again\n")
  val () = $B.bput(b, "    // with the intent it was first started with. Only while onCreate runs.\n")
  val () = $B.bput(b, "    private boolean launchHandedOver;\n")
  val () = $B.bput(b, "\n")
  val () = $B.bput(b, "    @Override\n")
  val () = $B.bput(b, "    public void onCreate(Bundle savedInstanceState) {\n")
  val () = $B.bput(b, "        launchHandedOver = savedInstanceState != null\n")
  val () = $B.bput(b, "            || (getIntent().getFlags() & Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0;\n")
  val () = $B.bput(b, "        // An earlier run's files go before super.onCreate, whose load()\n")
  val () = $B.bput(b, "        // hands the launch intent to onNewIntent: that is its one hand-over\n")
  val () = $B.bput(b, "        if (savedInstanceState == null) {\n")
  val () = $B.bput(b, "            File[] old = incoming().listFiles();\n")
  val () = $B.bput(b, "            if (old != null) for (File f : old) f.delete();\n")
  val () = $B.bput(b, "        }\n")
  val () = $B.bput(b, "        Log.i(TAG, savedInstanceState == null ? \"created\" : \"recreated\");\n")
  val () = $B.bput(b, "        super.onCreate(savedInstanceState);\n")
  val () = $B.bput(b, "        launchHandedOver = false;\n")
  val () = $B.bput(b, "        // At each window insets dispatch, the window's own insets' isVisible\n")
  val () = $B.bput(b, "        // of the status bar and of the navigation bar (not the insets the\n")
  val () = $B.bput(b, "        // web view is given, which Capacitor's SystemBars rewrites, and from\n")
  val () = $B.bput(b, "        // which androidx reads visibility below API 30), handed to the page\n")
  val () = $B.bput(b, "        // (bridge's batsNative.systemBars); the web view then takes the\n")
  val () = $B.bput(b, "        // insets as it does with no listener (its own onApplyWindowInsets)\n")
  val () = $B.bput(b, "        if (bridge != null && bridge.getWebView() != null)\n")
  val () = $B.bput(b, "            ViewCompat.setOnApplyWindowInsetsListener(bridge.getWebView(), (view, insets) -> {\n")
  val () = $B.bput(b, "                WindowInsetsCompat window = ViewCompat.getRootWindowInsets(view);\n")
  val () = $B.bput(b, "                if (window != null) reportBars(\"(globalThis.batsNative && globalThis.batsNative.systemBars ? globalThis.batsNative.systemBars(\"\n")
  val () = $B.bput(b, "                    + window.isVisible(WindowInsetsCompat.Type.statusBars()) + \",\"\n")
  val () = $B.bput(b, "                    + window.isVisible(WindowInsetsCompat.Type.navigationBars()) + \") : false)\");\n")
  val () = $B.bput(b, "                return ViewCompat.onApplyWindowInsets(view, insets);\n")
  val () = $B.bput(b, "            });\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "\n")
  val () = $B.bput(b, "    @Override\n")
  val () = $B.bput(b, "    protected void onNewIntent(Intent intent) {\n")
  val () = $B.bput(b, "        setIntent(intent);\n")
  val () = $B.bput(b, "        if (launchHandedOver) {\n")
  val () = $B.bput(b, "            // load()'s call, not the system's: neither the page nor\n")
  val () = $B.bput(b, "            // Capacitor's plugins (the App plugin's appUrlOpen, an address\n")
  val () = $B.bput(b, "            // the app was opened at) are given it again\n")
  val () = $B.bput(b, "            launchHandedOver = false;\n")
  val () = $B.bput(b, "            Log.i(TAG, \"the launch intent was handed over before\");\n")
  val () = $B.bput(b, "            return;\n")
  val () = $B.bput(b, "        }\n")
  val () = $B.bput(b, "        super.onNewIntent(intent);\n")
  val () = $B.bput(b, "        handle(intent);\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "\n")
  val () = $B.bput(b, "    // A volume key goes to the page first, as the keydown a browser would\n")
  val () = $B.bput(b, "    // send (AudioVolumeUp, AudioVolumeDown). When the page takes it\n")
  val () = $B.bput(b, "    // (preventDefault: a reader turning pages with it), that is all;\n")
  val () = $B.bput(b, "    // else the volume changes, as the key would have changed it.\n")
  val () = $B.bput(b, "    @Override\n")
  val () = $B.bput(b, "    public boolean dispatchKeyEvent(KeyEvent event) {\n")
  val () = $B.bput(b, "        int code = event.getKeyCode();\n")
  val () = $B.bput(b, "        if (code != KeyEvent.KEYCODE_VOLUME_UP && code != KeyEvent.KEYCODE_VOLUME_DOWN)\n")
  val () = $B.bput(b, "            return super.dispatchKeyEvent(event);\n")
  val () = $B.bput(b, "        if (bridge == null || bridge.getWebView() == null) return super.dispatchKeyEvent(event);\n")
  val () = $B.bput(b, "        if (event.getAction() != KeyEvent.ACTION_DOWN) return true;\n")
  val () = $B.bput(b, "        final boolean up = code == KeyEvent.KEYCODE_VOLUME_UP;\n")
  val () = $B.bput(b, "        final String js = \"(globalThis.batsNative ? globalThis.batsNative.key(\"\n")
  val () = $B.bput(b, "            + JSONObject.quote(up ? \"AudioVolumeUp\" : \"AudioVolumeDown\") + \") : false)\";\n")
  val () = $B.bput(b, "        bridge.getWebView().evaluateJavascript(js, r -> {\n")
  val () = $B.bput(b, "            boolean taken = \"true\".equals(r);\n")
  val () = $B.bput(b, "            Log.i(TAG, \"volume key: \" + (taken ? \"the page took it\" : \"the page left it\"));\n")
  val () = $B.bput(b, "            if (taken) return;\n")
  val () = $B.bput(b, "            AudioManager audio = (AudioManager) getSystemService(AUDIO_SERVICE);\n")
  val () = $B.bput(b, "            if (audio != null) audio.adjustSuggestedStreamVolume(\n")
  val () = $B.bput(b, "                up ? AudioManager.ADJUST_RAISE : AudioManager.ADJUST_LOWER,\n")
  val () = $B.bput(b, "                AudioManager.USE_DEFAULT_STREAM_TYPE, AudioManager.FLAG_SHOW_UI);\n")
  val () = $B.bput(b, "        });\n")
  val () = $B.bput(b, "        return true;\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "\n")
  val () = $B.bput(b, "    private File incoming() {\n")
  val () = $B.bput(b, "        File dir = new File(getCacheDir(), \"incoming\");\n")
  val () = $B.bput(b, "        dir.mkdirs();\n")
  val () = $B.bput(b, "        return dir;\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "\n")
  val () = $B.bput(b, "    private void handle(Intent intent) {\n")
  val () = $B.bput(b, "        if (intent == null) return;\n")
  val () = $B.bput(b, "        String action = intent.getAction();\n")
  val () = $B.bput(b, "        if (Intent.ACTION_VIEW.equals(action)) {\n")
  val () = $B.bput(b, "            // an address at the app's own scheme is not a file: Capacitor's\n")
  val () = $B.bput(b, "            // App plugin gives it to the page\n")
  val () = $B.bput(b, "            Uri data = intent.getData();\n")
  val () = $B.bput(b, "            if (data != null && (\"content\".equals(data.getScheme()) || \"file\".equals(data.getScheme()))) deliver(data);\n")
  val () = $B.bput(b, "        } else if (Intent.ACTION_SEND.equals(action)) {\n")
  val () = $B.bput(b, "            deliver((Uri) intent.getParcelableExtra(Intent.EXTRA_STREAM));\n")
  val () = $B.bput(b, "        } else if (Intent.ACTION_SEND_MULTIPLE.equals(action)) {\n")
  val () = $B.bput(b, "            ArrayList<Uri> uris = intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM);\n")
  val () = $B.bput(b, "            if (uris != null) for (Uri u : uris) deliver(u);\n")
  val () = $B.bput(b, "        }\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "\n")
  val () = $B.bput(b, "    private String nameOf(Uri uri) {\n")
  val () = $B.bput(b, "        String name = uri.getLastPathSegment();\n")
  val () = $B.bput(b, "        try (Cursor c = getContentResolver().query(uri, null, null, null, null)) {\n")
  val () = $B.bput(b, "            if (c != null && c.moveToFirst()) {\n")
  val () = $B.bput(b, "                int i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME);\n")
  val () = $B.bput(b, "                if (i >= 0 && c.getString(i) != null) name = c.getString(i);\n")
  val () = $B.bput(b, "            }\n")
  val () = $B.bput(b, "        } catch (Exception e) {\n")
  val () = $B.bput(b, "            // the name is only shown while the file is imported\n")
  val () = $B.bput(b, "        }\n")
  val () = $B.bput(b, "        return name == null ? \"\" : name;\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "\n")
  val () = $B.bput(b, "    private void deliver(final Uri uri) {\n")
  val () = $B.bput(b, "        Log.i(TAG, \"handed \" + uri);\n")
  val () = $B.bput(b, "        if (uri == null) return;\n")
  val () = $B.bput(b, "        new Thread(() -> {\n")
  val () = $B.bput(b, "            try {\n")
  val () = $B.bput(b, "                String name = nameOf(uri);\n")
  val () = $B.bput(b, "                File out = File.createTempFile(\"file\", \".bin\", incoming());\n")
  val () = $B.bput(b, "                try (InputStream in = getContentResolver().openInputStream(uri);\n")
  val () = $B.bput(b, "                     OutputStream os = new FileOutputStream(out)) {\n")
  val () = $B.bput(b, "                    byte[] buf = new byte[65536];\n")
  val () = $B.bput(b, "                    int n;\n")
  val () = $B.bput(b, "                    while ((n = in.read(buf)) > 0) os.write(buf, 0, n);\n")
  val () = $B.bput(b, "                }\n")
  val () = $B.bput(b, "                final String js = \"(globalThis.batsNative ? globalThis.batsNative.deliverFile(\"\n")
  val () = $B.bput(b, "                    + JSONObject.quote(\"/_capacitor_file_\" + out.getAbsolutePath())\n")
  val () = $B.bput(b, "                    + \",\" + JSONObject.quote(name) + \") : false)\";\n")
  val () = $B.bput(b, "                Log.i(TAG, \"copied \" + out.length() + \" bytes to \" + out);\n")
  val () = $B.bput(b, "                handler.post(() -> hand(js, 240));\n")
  val () = $B.bput(b, "            } catch (Exception e) {\n")
  val () = $B.bput(b, "                // a file that cannot be read is not handed over\n")
  val () = $B.bput(b, "                Log.w(TAG, \"cannot read \" + uri, e);\n")
  val () = $B.bput(b, "            }\n")
  val () = $B.bput(b, "        }).start();\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "\n")
  val () = $B.bput(b, "    // The latest report of the system bars the page has not taken yet\n")
  val () = $B.bput(b, "    private String barsReport;\n")
  val () = $B.bput(b, "\n")
  val () = $B.bput(b, "    private void reportBars(String js) {\n")
  val () = $B.bput(b, "        boolean idle = barsReport == null;\n")
  val () = $B.bput(b, "        barsReport = js;\n")
  val () = $B.bput(b, "        if (idle) handBars(240);\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "\n")
  val () = $B.bput(b, "    // Hands the latest report to the page once it has the bridge (every\n")
  val () = $B.bput(b, "    // quarter second, for a minute at most); one made meanwhile goes next\n")
  val () = $B.bput(b, "    private void handBars(final int tries) {\n")
  val () = $B.bput(b, "        final String js = barsReport;\n")
  val () = $B.bput(b, "        if (js == null || bridge == null || bridge.getWebView() == null) return;\n")
  val () = $B.bput(b, "        bridge.getWebView().evaluateJavascript(js, r -> {\n")
  val () = $B.bput(b, "            if (\"true\".equals(r)) {\n")
  val () = $B.bput(b, "                if (js.equals(barsReport)) barsReport = null;\n")
  val () = $B.bput(b, "                else handBars(tries);\n")
  val () = $B.bput(b, "            } else if (tries > 0) handler.postDelayed(() -> handBars(tries - 1), 250);\n")
  val () = $B.bput(b, "            else barsReport = null;\n")
  val () = $B.bput(b, "        });\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "\n")
  val () = $B.bput(b, "    // Runs js once the page has the bridge (every quarter second, for a\n")
  val () = $B.bput(b, "    // minute at most)\n")
  val () = $B.bput(b, "    private void hand(final String js, final int tries) {\n")
  val () = $B.bput(b, "        if (bridge == null || bridge.getWebView() == null) {\n")
  val () = $B.bput(b, "            if (tries > 0) handler.postDelayed(() -> hand(js, tries - 1), 250);\n")
  val () = $B.bput(b, "            return;\n")
  val () = $B.bput(b, "        }\n")
  val () = $B.bput(b, "        bridge.getWebView().evaluateJavascript(js, r -> {\n")
  val () = $B.bput(b, "            if (\"true\".equals(r)) Log.i(TAG, \"handed to the page\");\n")
  val () = $B.bput(b, "            else if (tries > 0) handler.postDelayed(() -> hand(js, tries - 1), 250);\n")
  val () = $B.bput(b, "            else Log.w(TAG, \"the page never took the file\");\n")
  val () = $B.bput(b, "        });\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "}\n")
in end

implement build_intent_filters (b, mime) = let
  val () = $B.bput(b, "            <intent-filter>\n")
  val () = $B.bput(b, "                <action android:name=\"android.intent.action.VIEW\" />\n")
  val () = $B.bput(b, "                <category android:name=\"android.intent.category.DEFAULT\" />\n")
  val () = $B.bput(b, "                <category android:name=\"android.intent.category.BROWSABLE\" />\n")
  val () = $B.bput(b, "                <data android:scheme=\"content\" />\n")
  val () = $B.bput(b, "                <data android:mimeType=\"")
  val () = $B.bput(b, mime)
  val () = $B.bput(b, "\" />\n")
  val () = $B.bput(b, "            </intent-filter>\n")
  val () = $B.bput(b, "            <intent-filter>\n")
  val () = $B.bput(b, "                <action android:name=\"android.intent.action.SEND\" />\n")
  val () = $B.bput(b, "                <action android:name=\"android.intent.action.SEND_MULTIPLE\" />\n")
  val () = $B.bput(b, "                <category android:name=\"android.intent.category.DEFAULT\" />\n")
  val () = $B.bput(b, "                <data android:mimeType=\"")
  val () = $B.bput(b, mime)
  val () = $B.bput(b, "\" />\n")
  val () = $B.bput(b, "            </intent-filter>\n")
in end

implement build_smoke_test_script (b, app_id) = let
  val () = $B.bput(b, "#!/bin/sh\n")
  val () = $B.bput(b, "# usage: smoke-test.sh <apk> <text> <out-dir> [<file> <type> <text>]\n")
  val () = $B.bput(b, "# On a running emulator or device (adb): installs the APK (signed\n")
  val () = $B.bput(b, "# with a throwaway key when unsigned), launches the app, and waits\n")
  val () = $B.bput(b, "# up to two minutes for <text> on the screen. Writes screenshot.png,\n")
  val () = $B.bput(b, "# ui.xml and logcat.txt to <out-dir>. Fails when the text never\n")
  val () = $B.bput(b, "# shows, the app crashes, or the page logs a console error. With\n")
  val () = $B.bput(b, "# <file> <type> <text>, then starts the app anew with the file (VIEW),\n")
  val () = $B.bput(b, "# waits for that text too, and checks that each intent's file is\n")
  val () = $B.bput(b, "# handed to the page once: as the app starts, not again when it is\n")
  val () = $B.bput(b, "# turned or recreated, and once each while it is open (VIEW, SEND).\n")
  val () = $B.bput(b, "set -eu\n")
  val () = $B.bput(b, "APP_ID='")
  val () = $B.bput(b, app_id)
  val () = $B.bput(b, "'\n")
  val () = $B.bput(b, "APK=$1\n")
  val () = $B.bput(b, "TEXT=$2\n")
  val () = $B.bput(b, "OUT=$3\n")
  val () = $B.bput(b, "mkdir -p \"$OUT\"\n")
  val () = $B.bput(b, "case \"$APK\" in\n")
  val () = $B.bput(b, "  *unsigned*)\n")
  val () = $B.bput(b, "    SIGNER=$(find \"$ANDROID_HOME/build-tools\" -name apksigner | sort | tail -1)\n")
  val () = $B.bput(b, "    keytool -genkeypair -keystore \"$OUT/smoke.jks\" -alias smoke -keyalg RSA \\\n")
  val () = $B.bput(b, "      -keysize 2048 -validity 1 -storepass smokepass -keypass smokepass \\\n")
  val () = $B.bput(b, "      -dname CN=smoke >/dev/null\n")
  val () = $B.bput(b, "    \"$SIGNER\" sign --ks \"$OUT/smoke.jks\" --ks-pass pass:smokepass \\\n")
  val () = $B.bput(b, "      --out \"$OUT/smoke-signed.apk\" \"$APK\"\n")
  val () = $B.bput(b, "    rm -f \"$OUT/smoke.jks\"\n")
  val () = $B.bput(b, "    APK=\"$OUT/smoke-signed.apk\"\n")
  val () = $B.bput(b, "    ;;\n")
  val () = $B.bput(b, "esac\n")
  val () = $B.bput(b, "# The emulator reports booted before Android has unlocked the user and\n")
  val () = $B.bput(b, "# sent BOOT_COMPLETED; an app launched then is relaunched as boot\n")
  val () = $B.bput(b, "# finishes, and its first page is torn down while it loads. Wait for\n")
  val () = $B.bput(b, "# boot, then for the broadcast queue (BOOT_COMPLETED's) to drain.\n")
  val () = $B.bput(b, "adb wait-for-device\n")
  val () = $B.bput(b, "until [ \"$(adb shell getprop sys.boot_completed | tr -d '\\r')\" = 1 ]; do sleep 2; done\n")
  val () = $B.bput(b, "timeout 300 adb shell am wait-for-broadcast-idle >/dev/null\n")
  val () = $B.bput(b, "adb install -r \"$APK\"\n")
  val () = $B.bput(b, "adb logcat -c\n")
  val () = $B.bput(b, "# Waits up to two minutes for $1 on the screen: found is 1 once it shows\n")
  val () = $B.bput(b, "shown() {\n")
  val () = $B.bput(b, "  found=0\n")
  val () = $B.bput(b, "  for _ in $(seq 60); do\n")
  val () = $B.bput(b, "    sleep 2\n")
  val () = $B.bput(b, "    adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || continue\n")
  val () = $B.bput(b, "    adb shell cat /sdcard/ui.xml > \"$OUT/ui.xml\" || continue\n")
  val () = $B.bput(b, "    if grep -qF \"$1\" \"$OUT/ui.xml\"; then found=1; return 0; fi\n")
  val () = $B.bput(b, "  done\n")
  val () = $B.bput(b, "}\n")
  val () = $B.bput(b, "# How many of the activity's log lines (tag BatsFiles) hold $1\n")
  val () = $B.bput(b, "logged() {\n")
  val () = $B.bput(b, "  adb logcat -d -s BatsFiles:I | grep -cF \"$1\" || true\n")
  val () = $B.bput(b, "}\n")
  val () = $B.bput(b, "failed=0\n")
  val () = $B.bput(b, "fail() {\n")
  val () = $B.bput(b, "  echo \"$1\"; failed=1\n")
  val () = $B.bput(b, "}\n")
  val () = $B.bput(b, "adb shell monkey -p \"$APP_ID\" -c android.intent.category.LAUNCHER 1 >/dev/null\n")
  val () = $B.bput(b, "shown \"$TEXT\"\n")
  val () = $B.bput(b, "# A volume key is offered to the page first (the activity logs whether\n")
  val () = $B.bput(b, "# the page took it); it must reach the page, and not crash the app\n")
  val () = $B.bput(b, "if [ $found = 1 ]; then\n")
  val () = $B.bput(b, "  adb shell input keyevent KEYCODE_VOLUME_DOWN\n")
  val () = $B.bput(b, "  volume=0\n")
  val () = $B.bput(b, "  for _ in $(seq 10); do\n")
  val () = $B.bput(b, "    sleep 1\n")
  val () = $B.bput(b, "    if [ \"$(logged \"volume key: the page\")\" -gt 0 ]; then volume=1; break; fi\n")
  val () = $B.bput(b, "  done\n")
  val () = $B.bput(b, "  if [ $volume = 0 ]; then fail \"A volume key never reached the page\"; fi\n")
  val () = $B.bput(b, "fi\n")
  val () = $B.bput(b, "# Waits up to two minutes until the activity has handed $1 files to the\n")
  val () = $B.bput(b, "# page since $2 were, then five seconds for any more; fails unless $1\n")
  val () = $B.bput(b, "# were, saying $3\n")
  val () = $B.bput(b, "handed() {\n")
  val () = $B.bput(b, "  for _ in $(seq 60); do\n")
  val () = $B.bput(b, "    if [ $(( $(logged \"handed to the page\") - $2 )) -ge \"$1\" ]; then break; fi\n")
  val () = $B.bput(b, "    sleep 2\n")
  val () = $B.bput(b, "  done\n")
  val () = $B.bput(b, "  sleep 5\n")
  val () = $B.bput(b, "  n=$(( $(logged \"handed to the page\") - $2 ))\n")
  val () = $B.bput(b, "  if [ \"$n\" != \"$1\" ]; then fail \"$3: the activity handed $n files to the page, not $1\"; fi\n")
  val () = $B.bput(b, "}\n")
  val () = $B.bput(b, "# The file is put in the app's cache (adb as root, on an emulator) and\n")
  val () = $B.bput(b, "# handed to the app as another app would, each time to be handed to\n")
  val () = $B.bput(b, "# the page once (bats-lang/quire#247)\n")
  val () = $B.bput(b, "if [ $found = 1 ] && [ $# -ge 6 ]; then\n")
  val () = $B.bput(b, "  TEXT=$6\n")
  val () = $B.bput(b, "  DEST=\"/data/data/$APP_ID/cache/smoke-share\"\n")
  val () = $B.bput(b, "  adb root >/dev/null\n")
  val () = $B.bput(b, "  adb wait-for-device\n")
  val () = $B.bput(b, "  adb push \"$4\" /data/local/tmp/smoke-share >/dev/null\n")
  val () = $B.bput(b, "  OWNER=$(adb shell stat -c %u \"/data/data/$APP_ID\" | tr -d '\\r')\n")
  val () = $B.bput(b, "  adb shell \"cp /data/local/tmp/smoke-share $DEST && chown $OWNER:$OWNER $DEST && restorecon $DEST\"\n")
  val () = $B.bput(b, "  # Started anew with the file, as a file manager opens it: one\n")
  val () = $B.bput(b, "  # hand-over, and one copy of the file in the cache\n")
  val () = $B.bput(b, "  adb shell am force-stop \"$APP_ID\"\n")
  val () = $B.bput(b, "  start=$(logged \"handed to the page\")\n")
  val () = $B.bput(b, "  adb shell am start -W -a android.intent.action.VIEW -d \"file://$DEST\" -t \"$5\" -n \"$APP_ID/.MainActivity\" >/dev/null\n")
  val () = $B.bput(b, "  shown \"$TEXT\"\n")
  val () = $B.bput(b, "fi\n")
  val () = $B.bput(b, "if [ $found = 1 ] && [ $# -ge 6 ]; then\n")
  val () = $B.bput(b, "  handed 1 \"$start\" \"Started with the file\"\n")
  val () = $B.bput(b, "  copies=$(adb shell ls \"/data/data/$APP_ID/cache/incoming\" | wc -l)\n")
  val () = $B.bput(b, "  if [ \"$copies\" -ne 1 ]; then fail \"Started with the file, the app copied it $copies times\"; fi\n")
  val () = $B.bput(b, "  # Turned, then recreated (by a font scale, which Capacitor's activity\n")
  val () = $B.bput(b, "  # does not take itself): the file it was started with is not handed\n")
  val () = $B.bput(b, "  # over again\n")
  val () = $B.bput(b, "  recreated=$(logged \"recreated\")\n")
  val () = $B.bput(b, "  adb shell settings put system accelerometer_rotation 0\n")
  val () = $B.bput(b, "  adb shell settings put system user_rotation 1\n")
  val () = $B.bput(b, "  sleep 5\n")
  val () = $B.bput(b, "  adb shell settings put system font_scale 1.15\n")
  val () = $B.bput(b, "  for _ in $(seq 30); do\n")
  val () = $B.bput(b, "    sleep 1\n")
  val () = $B.bput(b, "    if [ \"$(logged \"recreated\")\" -gt \"$recreated\" ]; then break; fi\n")
  val () = $B.bput(b, "  done\n")
  val () = $B.bput(b, "  if [ \"$(logged \"recreated\")\" -le \"$recreated\" ]; then fail \"The activity was never recreated\"; fi\n")
  val () = $B.bput(b, "  shown \"$TEXT\"\n")
  val () = $B.bput(b, "  handed 1 \"$start\" \"Turned and recreated\"\n")
  val () = $B.bput(b, "  adb shell settings put system font_scale 1.0\n")
  val () = $B.bput(b, "  adb shell settings put system user_rotation 0\n")
  val () = $B.bput(b, "  shown \"$TEXT\"\n")
  val () = $B.bput(b, "  # While it is open, opened with the file and shared it: each once\n")
  val () = $B.bput(b, "  adb shell am start -a android.intent.action.VIEW -d \"file://$DEST\" -t \"$5\" -n \"$APP_ID/.MainActivity\" >/dev/null\n")
  val () = $B.bput(b, "  handed 2 \"$start\" \"Opened with the file while open\"\n")
  val () = $B.bput(b, "  adb shell am start -a android.intent.action.SEND -t \"$5\" --eu android.intent.extra.STREAM \"file://$DEST\" -n \"$APP_ID/.MainActivity\" >/dev/null\n")
  val () = $B.bput(b, "  handed 3 \"$start\" \"Shared the file while open\"\n")
  val () = $B.bput(b, "fi\n")
  val () = $B.bput(b, "adb exec-out screencap -p > \"$OUT/screenshot.png\"\n")
  val () = $B.bput(b, "adb logcat -d > \"$OUT/logcat.txt\"\n")
  val () = $B.bput(b, "status=$failed\n")
  val () = $B.bput(b, "# The app crashed when AndroidRuntime's FATAL EXCEPTION names its\n")
  val () = $B.bput(b, "# process on the next line; another process's (uiautomator's own, say)\n")
  val () = $B.bput(b, "# is not the app's\n")
  val () = $B.bput(b, "if grep -A1 \"FATAL EXCEPTION\" \"$OUT/logcat.txt\" | grep -q \"Process: $APP_ID,\"; then\n")
  val () = $B.bput(b, "  echo \"The app crashed:\"; grep -A20 \"FATAL EXCEPTION\" \"$OUT/logcat.txt\"; status=1\n")
  val () = $B.bput(b, "fi\n")
  val () = $B.bput(b, "# Capacitor logs the page's console.error with level E and tag Capacitor/Console\n")
  val () = $B.bput(b, "if grep -E \" E Capacitor/Console\" \"$OUT/logcat.txt\"; then\n")
  val () = $B.bput(b, "  echo \"The page logged console errors (above)\"; status=1\n")
  val () = $B.bput(b, "fi\n")
  val () = $B.bput(b, "if [ $found = 0 ]; then\n")
  val () = $B.bput(b, "  echo \"'$TEXT' was not on the screen after two minutes\"; status=1\n")
  val () = $B.bput(b, "  echo \"The app's file hand-over and page console:\"\n")
  val () = $B.bput(b, "  grep -E \" (BatsFiles|Capacitor[^ ]*) *:\" \"$OUT/logcat.txt\" | tail -40\n")
  val () = $B.bput(b, "else\n")
  val () = $B.bput(b, "  echo \"'$TEXT' is on the screen\"\n")
  val () = $B.bput(b, "fi\n")
  val () = $B.bput(b, "exit $status\n")
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
  case+ _open_built(db, $F.WriteOnly(), $F.CreateOrTruncate(), 420) of
  | ~$R.ok(fd) => let
      var sb = $B.create()
      val () = _put_range(assets, p, e, sb)
      val () = $B.put_char(sb, 0)
      val () = _copy_from(sb, fd)
    in $R.discard<int><$F.io_error>($F.file_close(fd)) end
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

implement create_pwa_opening (app_name, app_id, wasm_path, wasm_name, out_dir, assets, asset_len, asset_max, mime, ext) = let
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
  val () = build_manifest_opening(mf_b, app_name, mime, ext)
  val () = _write_to(out_dir, "manifest.json", mf_b)
  val () = _copy_to(wasm_path, out_dir, wasm_name)
  val () = _copy_assets(assets, 0, asset_len, out_dir)
in end

implement create_android (app_name, app_id, web_dir, project_dir, mime) = let
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
  var ma_b = $B.create()
  val () = build_main_activity(ma_b, app_id)
  val () = _write_to(project_dir, "MainActivity.java", ma_b)
  var if_b = $B.create()
  val () = build_intent_filters(if_b, mime)
  val () = _write_to(project_dir, "intent-filters.xml", if_b)
  (* the backup rules the manifest names: bridge's, since bridge keeps
     the files they name (its backup_file) *)
  var full_backup_b = $B.create()
  val () = $BR.produce_full_backup_content(full_backup_b)
  val () = _write_to(project_dir, "backup-rules.xml", full_backup_b)
  var extraction_b = $B.create()
  val () = $BR.produce_data_extraction_rules(extraction_b)
  val () = _write_to(project_dir, "data-extraction-rules.xml", extraction_b)
  var sh_b = $B.create()
  val () = build_android_script(sh_b, web_dir)
  val () = _write_mode(project_dir, "build-android.sh", sh_b, 493)
  var st_b = $B.create()
  val () = build_smoke_test_script(st_b, app_id)
in _write_mode(project_dir, "smoke-test.sh", st_b, 493) end
