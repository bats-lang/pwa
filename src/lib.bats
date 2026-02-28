(* pwa -- PWA shell generator for bats WASM apps *)
(* Generates index.html, service-worker.js, manifest.json *)
(* Safe: no $UNSAFE, no $extfcall *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use wasm.bats-packages.dev/bridge as BR

(* Copy string into builder *)
fun bput_loop {sn:nat}{fuel:nat} .<fuel>.
  (b: !$B.builder, s: string sn, slen: int sn, i: int, fuel: int fuel): void =
  if fuel <= 0 then ()
  else let
    val ii = $AR.checked_idx(i, slen)
    val c = char2int0(string_get_at(s, ii))
    val () = $B.put_byte(b, c)
  in bput_loop(b, s, slen, i + 1, fuel - 1) end

fn bput {sn:nat} (b: !$B.builder, s: string sn): void = let
  val slen_sz = string1_length(s)
  val slen = g1u2i(slen_sz)
in bput_loop(b, s, slen, 0, $AR.checked_nat(g0ofg1(slen) + 1)) end

(* ============================================================
   Public API
   ============================================================ *)

(* Generate index.html into builder.
   app_name: displayed in loading screen and title
   wasm_file: filename of the .wasm file (e.g. "output.wasm") *)
#pub fn build_html {na:nat}{nw:nat}
  (b: !$B.builder, app_name: string na, wasm_file: string nw): void

(* Generate service-worker.js into builder.
   wasm_file: filename to cache *)
#pub fn build_service_worker {nw:nat}
  (b: !$B.builder, wasm_file: string nw): void

(* Generate manifest.json into builder.
   app_name: PWA name *)
#pub fn build_manifest {na:nat}
  (b: !$B.builder, app_name: string na): void

(* ============================================================
   Implementations
   ============================================================ *)

implement build_html (b, app_name, wasm_file) = let
  val () = bput(b, "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n")
  val () = bput(b, "  <meta charset=\"UTF-8\">\n")
  val () = bput(b, "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n")
  val () = bput(b, "  <title>")
  val () = bput(b, app_name)
  val () = bput(b, "</title>\n")
  val () = bput(b, "  <meta name=\"theme-color\" content=\"#ffffff\">\n")
  val () = bput(b, "  <link rel=\"manifest\" href=\"manifest.json\">\n")
  val () = bput(b, "  <style>\n")
  (* Loading spinner CSS *)
  val () = bput(b, "    body { margin: 0; font-family: system-ui, sans-serif; }\n")
  val () = bput(b, "    .loading { display: flex; flex-direction: column; align-items: center;\n")
  val () = bput(b, "      justify-content: center; height: 100vh; }\n")
  val () = bput(b, "    .spinner { width: 40px; height: 40px; border: 4px solid #eee;\n")
  val () = bput(b, "      border-top-color: #333; border-radius: 50%;\n")
  val () = bput(b, "      animation: spin 0.8s linear infinite; }\n")
  val () = bput(b, "    @keyframes spin { to { transform: rotate(360deg); } }\n")
  val () = bput(b, "    .app-name { margin-top: 16px; font-size: 18px; color: #666; }\n")
  val () = bput(b, "  </style>\n")
  val () = bput(b, "</head>\n<body>\n")
  val () = bput(b, "  <div id=\"app\">\n")
  val () = bput(b, "    <div class=\"loading\">\n")
  val () = bput(b, "      <div class=\"spinner\"></div>\n")
  val () = bput(b, "      <div class=\"app-name\">")
  val () = bput(b, app_name)
  val () = bput(b, "</div>\n")
  val () = bput(b, "    </div>\n")
  val () = bput(b, "  </div>\n")
  (* Bridge JS — inline the full bridge *)
  val () = bput(b, "  <script type=\"module\">\n")
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
      val p = $AR.checked_idx(i, 524288)
      val byte_val = byte2int0($A.read<byte>(bv, p))
      val () = $B.put_byte(out, byte_val)
    in copy_bridge(bv, i + 1, len, out, fuel - 1) end
  val () = copy_bridge(bv_br, 0, bridge_len, b, $AR.checked_nat(bridge_len + 1))
  val () = $A.drop<byte>(fz_br, bv_br)
  val () = $A.free<byte>($A.thaw<byte>(fz_br))
  val () = bput(b, "\n")
  (* App bootstrap *)
  val () = bput(b, "    const root = document.getElementById('app');\n")
  val () = bput(b, "    const resp = await fetch('")
  val () = bput(b, wasm_file)
  val () = bput(b, "');\n")
  val () = bput(b, "    const bytes = await resp.arrayBuffer();\n")
  val () = bput(b, "    await loadWard(bytes, root, {});\n")
  val () = bput(b, "  </script>\n")
  (* Service worker registration *)
  val () = bput(b, "  <script>\n")
  val () = bput(b, "    if ('serviceWorker' in navigator) {\n")
  val () = bput(b, "      navigator.serviceWorker.register('service-worker.js');\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "  </script>\n")
  val () = bput(b, "</body>\n</html>\n")
in end

implement build_service_worker (b, wasm_file) = let
  val () = bput(b, "const CACHE = 'bats-pwa-v1';\n")
  val () = bput(b, "const SHELL = [\n")
  val () = bput(b, "  './', '")
  val () = bput(b, wasm_file)
  val () = bput(b, "', 'manifest.json',\n")
  val () = bput(b, "];\n\n")
  val () = bput(b, "self.addEventListener('install', e => {\n")
  val () = bput(b, "  self.skipWaiting();\n")
  val () = bput(b, "  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)));\n")
  val () = bput(b, "});\n\n")
  val () = bput(b, "self.addEventListener('activate', e => {\n")
  val () = bput(b, "  e.waitUntil(\n")
  val () = bput(b, "    caches.keys().then(keys =>\n")
  val () = bput(b, "      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))\n")
  val () = bput(b, "    ).then(() => self.clients.claim())\n")
  val () = bput(b, "  );\n")
  val () = bput(b, "});\n\n")
  val () = bput(b, "self.addEventListener('fetch', e => {\n")
  val () = bput(b, "  e.respondWith(caches.match(e.request).then(r => r || fetch(e.request)));\n")
  val () = bput(b, "});\n")
in end

implement build_manifest (b, app_name) = let
  val () = bput(b, "{\n")
  val () = bput(b, "  \"name\": \"")
  val () = bput(b, app_name)
  val () = bput(b, "\",\n")
  val () = bput(b, "  \"short_name\": \"")
  val () = bput(b, app_name)
  val () = bput(b, "\",\n")
  val () = bput(b, "  \"start_url\": \".\",\n")
  val () = bput(b, "  \"display\": \"standalone\",\n")
  val () = bput(b, "  \"background_color\": \"#ffffff\",\n")
  val () = bput(b, "  \"theme_color\": \"#ffffff\"\n")
  val () = bput(b, "}\n")
in end
