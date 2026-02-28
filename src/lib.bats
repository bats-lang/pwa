(* pwa -- PWA and APK shell generator for bats WASM apps *)
(* Generates index.html, service-worker.js, manifest.json, capacitor.config.json *)
(* Safe: no $UNSAFE, no $extfcall *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use file as F
#use result as R
#use wasm.bats-packages.dev/bridge as BR

(* ============================================================
   Builder-based API (generate file contents)
   ============================================================ *)

(* Generate index.html into builder.
   app_name: displayed in loading screen and title
   wasm_file: filename of the .wasm file (e.g. "output.wasm") *)
#pub fn build_html {na:nat}{nw:nat}
  (b: !$B.builder, app_name: string na, wasm_file: string nw): void

(* Generate service-worker.js into builder.
   wasm_file: filename to cache
   assets: null-separated list of extra paths to cache *)
#pub fn build_service_worker {nw:nat}
  (b: !$B.builder, wasm_file: string nw): void

(* Generate manifest.json into builder.
   app_name: PWA name *)
#pub fn build_manifest {na:nat}
  (b: !$B.builder, app_name: string na): void

(* Generate capacitor.config.json into builder.
   app_name: display name
   app_id: reverse-domain identifier (e.g. "com.example.myapp")
   out_dir: web content directory name (e.g. "dist") *)
#pub fn build_capacitor_config {na:nat}{ni:nat}{nd:nat}
  (b: !$B.builder, app_name: string na, app_id: string ni, out_dir: string nd): void

(* ============================================================
   High-level API (write files to directory)
   ============================================================ *)

(* Create a complete PWA in out_dir.
   Writes: index.html, service-worker.js, manifest.json, bridge.js
   Copies wasm_file to out_dir.
   wasm_path: path to the .wasm file
   wasm_name: filename for the wasm in the output (e.g. "app.wasm")
   out_dir: output directory path (must exist) *)
#pub fn create_pwa {na:nat}{ni:nat}{nw:nat}{nd:nat}
  (app_name: string na, app_id: string ni,
   wasm_path: string nw, wasm_name: string nd,
   out_dir: string na): void

(* Create a Capacitor-based APK project in out_dir.
   Same as create_pwa plus capacitor.config.json *)
#pub fn create_apk {na:nat}{ni:nat}{nw:nat}{nd:nat}
  (app_name: string na, app_id: string ni,
   wasm_path: string nw, wasm_name: string nd,
   out_dir: string na): void

(* ============================================================
   Implementations -- builder API
   ============================================================ *)

implement build_html (b, app_name, wasm_file) = let
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
  val () = $B.bput(b, "  <div id=\"app\">\n")
  val () = $B.bput(b, "    <div class=\"loading\">\n")
  val () = $B.bput(b, "      <div class=\"spinner\"></div>\n")
  val () = $B.bput(b, "      <div class=\"app-name\">")
  val () = $B.bput(b, app_name)
  val () = $B.bput(b, "</div>\n")
  val () = $B.bput(b, "    </div>\n")
  val () = $B.bput(b, "  </div>\n")
  val () = $B.bput(b, "  <script type=\"module\">\n")
  (* Emit the bridge JS source *)
  val bridge_b = $B.create()
  val () = $BR.produce_bridge(bridge_b)
  val @(bridge_arr, bridge_len) = $B.to_arr(bridge_b)
  val @(fz_br, bv_br) = $A.freeze<byte>(bridge_arr)
  fun copy_bridge {l:agz}{fuel:nat} .<fuel>.
    (bv: !$A.borrow(byte, l, 524288), i: int, len: int,
     out: !$B.builder, fuel: int fuel): void =
    if fuel <= 0 then ()
    else if i >= len then ()
    else let
      val byte_val = byte2int0($A.read<byte>(bv, $AR.checked_idx(i, 524288)))
      val () = $B.put_byte(out, byte_val)
    in copy_bridge(bv, i + 1, len, out, fuel - 1) end
  val () = copy_bridge(bv_br, 0, bridge_len, b, $AR.checked_nat(bridge_len + 1))
  val () = $A.drop<byte>(fz_br, bv_br)
  val () = $A.free<byte>($A.thaw<byte>(fz_br))
  val () = $B.bput(b, "\n")
  val () = $B.bput(b, "    const root = document.getElementById('app');\n")
  val () = $B.bput(b, "    const resp = await fetch('")
  val () = $B.bput(b, wasm_file)
  val () = $B.bput(b, "');\n")
  val () = $B.bput(b, "    const bytes = await resp.arrayBuffer();\n")
  val () = $B.bput(b, "    await loadWASM(bytes, root, {});\n")
  val () = $B.bput(b, "  </script>\n")
  val () = $B.bput(b, "  <script>\n")
  val () = $B.bput(b, "    if ('serviceWorker' in navigator) {\n")
  val () = $B.bput(b, "      navigator.serviceWorker.register('service-worker.js');\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "  </script>\n")
  val () = $B.bput(b, "</body>\n</html>\n")
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

(* ============================================================
   Implementations -- high-level file API
   ============================================================ *)

(* Helper: write builder contents to a file path *)
fn _write_builder_to_file {l:agz}{n:pos}
  (path: !$A.borrow(byte, l, n), path_len: int n, b: $B.builder): void = let
  val @(arr, len) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(arr)
  val fd_r = $F.file_create(path, path_len)
in
  case+ fd_r of
  | ~$R.ok(fd) => let
      val wr = $F.file_write(fd, bv, len)
      val () = $R.discard<int><int>(wr)
      val cr = $F.file_close(fd)
      val () = $R.discard<int><int>(cr)
    in
      $A.drop<byte>(fz, bv);
      $A.free<byte>($A.thaw<byte>(fz))
    end
  | ~$R.err(_) => let
    in
      $A.drop<byte>(fz, bv);
      $A.free<byte>($A.thaw<byte>(fz))
    end
end

implement create_pwa (app_name, app_id, wasm_path, wasm_name, out_dir) = let
  (* TODO: build paths by concatenating out_dir + "/" + filename *)
  (* For now, write to current directory *)
  val html_b = $B.create()
  val () = build_html(html_b, app_name, wasm_name)
  val sw_b = $B.create()
  val () = build_service_worker(sw_b, wasm_name)
  val mf_b = $B.create()
  val () = build_manifest(mf_b, app_name)
in end

implement create_apk (app_name, app_id, wasm_path, wasm_name, out_dir) = let
  val () = create_pwa(app_name, app_id, wasm_path, wasm_name, out_dir)
  val cap_b = $B.create()
  val () = build_capacitor_config(cap_b, app_name, app_id, out_dir)
in end
