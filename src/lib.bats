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

#pub fn build_html {na:nat | na < 256}{n:nat | n + 24400 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 24400] $B.builder(m), app_name: string na): void

#pub fn build_manifest {na:nat | na < 256}{n:nat | n + 900 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 900] $B.builder(m), app_name: string na): void

(* capacitor.config.json: the app's name and id, and web_dir, the PWA's
   directory relative to the Capacitor project's *)
#pub fn build_capacitor_config {na:nat | na < 256}{ni:nat | ni < 256}{nd:nat | nd < 256}{n:nat | n + 1200 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 1200] $B.builder(m), app_name: string na, app_id: string ni, web_dir: string nd): void

(* package.json of the Capacitor project: Capacitor 8's core, Android
   platform and CLI *)
#pub fn build_capacitor_package {n:nat | n + 700 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 700] $B.builder(m)): void

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
   release AAB and APK (npm install, cap add android, the app's own
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
   batsFetchExternal (the bridge's external files), once the page has
   it. *)
#pub fn build_main_activity {ni:nat | ni < 256}{n:nat | n + 7000 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 7000] $B.builder(m), app_id: string ni): void

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

(* smoke-test.sh, for app app_id: on a running emulator or device
   (adb), installs the APK given as its first argument (signing it with
   a throwaway key when it is unsigned), launches it, and waits up to
   two minutes for the text given as its second argument to be on the
   screen; writes screenshot.png, ui.xml and logcat.txt to the directory
   given as its third. With a fourth, fifth and sixth (a file, its type
   and a text), it then shares the file with the app (SEND, on an
   emulator where adb can be root) and waits for that text too. Fails
   when a text never shows, the app crashes, or the page logs an error
   to the console. *)
#pub fn build_smoke_test_script {ni:nat | ni < 256}{n:nat | n + 7000 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 7000] $B.builder(m), app_id: string ni): void

(* Writes a Capacitor project in project_dir for the PWA in web_dir
   (relative to project_dir): capacitor.config.json, package.json,
   android-release.gradle, MainActivity.java, intent-filters.xml,
   build-android.sh and smoke-test.sh. Running build-android.sh (Node,
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

(* Sharing (Web Share, or the Capacitor Share plugin in the Android
   app, whose WebView has no navigator.share): the root is marked
   pwa-can-share. A click on an element marked
   data-pwa-share-selection shares the selection, quoted, with the text
   of the element it names as its citation; one marked
   data-pwa-share-file, the text of the element it names as a Markdown
   file named by data-pwa-share-name (as its text where files cannot be
   shared). It is taken in the bubbling phase,
   after the app's own listener has written what is shared *)
fn _share_script {n:nat | n + 4000 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 4000] $B.builder(m)): void = let
  val () = $B.bput(b, "  <script>\n")
  val () = $B.bput(b, "    (function () {\n")
  val () = $B.bput(b, "      var root = document.documentElement;\n")
  val () = $B.bput(b, "      var plugin = window.Capacitor && Capacitor.Plugins && Capacitor.Plugins.Share;\n")
  val () = $B.bput(b, "      if (!navigator.share && !plugin) return;\n")
  val () = $B.bput(b, "      root.classList.add('pwa-can-share');\n")
  val () = $B.bput(b, "      var files = false;\n")
  val () = $B.bput(b, "      try { files = !!(navigator.canShare && navigator.canShare({ files: [new File(['.'], 'a.md', { type: 'text/markdown' })] })); } catch (e) {}\n")
  val () = $B.bput(b, "      function share(d) {\n")
  val () = $B.bput(b, "        var p = navigator.share ? navigator.share(d) : plugin.share({ title: d.title, text: d.text });\n")
  val () = $B.bput(b, "        if (p && p.catch) p.catch(function () {});\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      document.addEventListener('click', function (e) {\n")
  val () = $B.bput(b, "        var t = e.target && e.target.closest && e.target.closest('[data-pwa-share-selection],[data-pwa-share-file]');\n")
  val () = $B.bput(b, "        if (!t) return;\n")
  val () = $B.bput(b, "        if (t.hasAttribute('data-pwa-share-selection')) {\n")
  val () = $B.bput(b, "          var s = String(window.getSelection() || '').trim();\n")
  val () = $B.bput(b, "          if (!s) return;\n")
  val () = $B.bput(b, "          var c = document.getElementById(t.getAttribute('data-pwa-share-selection'));\n")
  val () = $B.bput(b, "          var cite = c ? c.textContent.trim() : '';\n")
  val () = $B.bput(b, "          return share({ text: '\\u201c' + s + '\\u201d' + (cite ? '\\n\\u2014 ' + cite : '') });\n")
  val () = $B.bput(b, "        }\n")
  val () = $B.bput(b, "        var src = document.getElementById(t.getAttribute('data-pwa-share-file'));\n")
  val () = $B.bput(b, "        var text = src ? src.textContent : '';\n")
  val () = $B.bput(b, "        if (!text) return;\n")
  val () = $B.bput(b, "        var name = t.getAttribute('data-pwa-share-name') || 'shared.md';\n")
  val () = $B.bput(b, "        if (files) share({ files: [new File([text], name, { type: 'text/markdown' })], title: name });\n")
  val () = $B.bput(b, "        else share({ title: name, text: text });\n")
  val () = $B.bput(b, "      });\n")
  val () = $B.bput(b, "    })();\n")
in $B.bput(b, "  </script>\n") end

(* Reading aloud, for an app that offers it (the Web Speech API): the
   root is marked pwa-can-speak where the browser speaks. A click on an
   element marked data-pwa-speak reads the element it names aloud, from
   the first sentence on screen (or pauses it, and a click again goes on
   where it was, if that is still on screen); on one marked
   data-pwa-speak-selection, from the sentence the selection starts in.
   It reads a sentence at a time (Intl.Segmenter), marked as the CSS
   highlight pwa-spoken while it is read; when the next one is not on
   screen it clicks the element marked data-pwa-speech-next (the app's
   own next page, so the app turns it, into the next chapter too), and it
   stops where that turns nothing. It speaks in the language of the text
   (its lang), in the voice and at the speed chosen in the selects marked
   data-pwa-speech-voice (naming the element read, whose language's
   voices it offers) and data-pwa-speech-rate, which it fills and keeps
   (localStorage), keeps the screen awake meanwhile (wake lock), and
   marks the root pwa-speaking and the speak elements aria-pressed *)
fn _speech_script {n:nat | n + 16000 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 16000] $B.builder(m)): void = let
  val () = $B.bput(b, "  <script>\n")
  val () = $B.bput(b, "    (function () {\n")
  val () = $B.bput(b, "      var synth = window.speechSynthesis;\n")
  val () = $B.bput(b, "      if (!synth || !window.SpeechSynthesisUtterance) return;\n")
  val () = $B.bput(b, "      var root = document.documentElement;\n")
  val () = $B.bput(b, "      root.classList.add('pwa-can-speak');\n")
  val () = $B.bput(b, "      var RATES = [0.75, 1, 1.25, 1.5, 1.75, 2];\n")
  val () = $B.bput(b, "      var BLOCKS = 'p,h1,h2,h3,h4,h5,h6,li,blockquote,dt,dd,figcaption,td,th,pre';\n")
  val () = $B.bput(b, "      var run = null, wake = null;\n")
  val () = $B.bput(b, "      function kept(k, v) {\n")
  val () = $B.bput(b, "        try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch (e) {}\n")
  val () = $B.bput(b, "        return null;\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      function langOf(box) {\n")
  val () = $B.bput(b, "        var e = box.querySelector('[lang]') || box.closest('[lang]');\n")
  val () = $B.bput(b, "        return ((e && e.getAttribute('lang')) || navigator.language || 'en').toLowerCase();\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      function same(a, b) { return a.split('-')[0] === b.split('-')[0]; }\n")
  val () = $B.bput(b, "      function voices(lang) {\n")
  val () = $B.bput(b, "        return synth.getVoices().filter(function (v) { return same(v.lang.toLowerCase(), lang); });\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      function rate() { return +(kept('pwa-speech-rate') || 1) || 1; }\n")
  val () = $B.bput(b, "      function voice(lang) {\n")
  val () = $B.bput(b, "        var want = kept('pwa-speech-voice:' + lang.split('-')[0]);\n")
  val () = $B.bput(b, "        var vs = voices(lang);\n")
  val () = $B.bput(b, "        return vs.filter(function (v) { return v.voiceURI === want; })[0] || vs.filter(function (v) { return v.default; })[0] || vs[0] || null;\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      function fill(s) {\n")
  val () = $B.bput(b, "        s.textContent = '';\n")
  val () = $B.bput(b, "        if (s.hasAttribute('data-pwa-speech-rate')) {\n")
  val () = $B.bput(b, "          RATES.forEach(function (r) { s.add(new Option(r + '×', String(r), false, r === rate())); });\n")
  val () = $B.bput(b, "          return;\n")
  val () = $B.bput(b, "        }\n")
  val () = $B.bput(b, "        var box = document.getElementById(s.getAttribute('data-pwa-speech-voice'));\n")
  val () = $B.bput(b, "        var lang = box ? langOf(box) : (navigator.language || 'en').toLowerCase();\n")
  val () = $B.bput(b, "        var cur = voice(lang);\n")
  val () = $B.bput(b, "        s.add(new Option('Automatic', ''));\n")
  val () = $B.bput(b, "        voices(lang).forEach(function (v) { s.add(new Option(v.name, v.voiceURI, false, cur === v && !!kept('pwa-speech-voice:' + lang.split('-')[0]))); });\n")
  val () = $B.bput(b, "        s.dataset.pwaLang = lang;\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      function fillAll() {\n")
  val () = $B.bput(b, "        document.querySelectorAll('select[data-pwa-speech-rate],select[data-pwa-speech-voice]').forEach(fill);\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      if (synth.addEventListener) synth.addEventListener('voiceschanged', fillAll);\n")
  val () = $B.bput(b, "      document.addEventListener('focusin', function (e) {\n")
  val () = $B.bput(b, "        var s = e.target;\n")
  val () = $B.bput(b, "        if (s && s.matches && s.matches('select[data-pwa-speech-rate],select[data-pwa-speech-voice]')) fill(s);\n")
  val () = $B.bput(b, "      }, true);\n")
  val () = $B.bput(b, "      document.addEventListener('change', function (e) {\n")
  val () = $B.bput(b, "        var s = e.target;\n")
  val () = $B.bput(b, "        if (!s || !s.matches) return;\n")
  val () = $B.bput(b, "        if (s.matches('select[data-pwa-speech-rate]')) kept('pwa-speech-rate', s.value);\n")
  val () = $B.bput(b, "        else if (s.matches('select[data-pwa-speech-voice]')) kept('pwa-speech-voice:' + (s.dataset.pwaLang || 'en').split('-')[0], s.value);\n")
  val () = $B.bput(b, "        else return;\n")
  val () = $B.bput(b, "        if (run && !run.paused) { var r = run; stop(true); r.paused = false; play(r); }\n")
  val () = $B.bput(b, "      }, true);\n")
  val () = $B.bput(b, "      new MutationObserver(function () {\n")
  val () = $B.bput(b, "        document.querySelectorAll('select[data-pwa-speech-rate]:empty,select[data-pwa-speech-voice]:empty').forEach(fill);\n")
  val () = $B.bput(b, "      }).observe(document.documentElement, { childList: true, subtree: true });\n")
  val () = $B.bput(b, "    \n")
  val () = $B.bput(b, "      // The block elements of box, in order, from the one holding node (or\n")
  val () = $B.bput(b, "      // the first)\n")
  val () = $B.bput(b, "      function blocks(box) {\n")
  val () = $B.bput(b, "        return Array.prototype.filter.call(box.querySelectorAll(BLOCKS), function (e) {\n")
  val () = $B.bput(b, "          return !e.querySelector(BLOCKS) && /\\S/.test(e.textContent);\n")
  val () = $B.bput(b, "        });\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      // A block's sentences: their text and ranges\n")
  val () = $B.bput(b, "      function sentences(block, lang) {\n")
  val () = $B.bput(b, "        var nodes = [], text = '', w = document.createTreeWalker(block, NodeFilter.SHOW_TEXT), n;\n")
  val () = $B.bput(b, "        while ((n = w.nextNode())) { nodes.push({ node: n, at: text.length }); text += n.data; }\n")
  val () = $B.bput(b, "        var spans = [];\n")
  val () = $B.bput(b, "        if (window.Intl && Intl.Segmenter) {\n")
  val () = $B.bput(b, "          var seg = new Intl.Segmenter(lang, { granularity: 'sentence' }).segment(text);\n")
  val () = $B.bput(b, "          for (var it = seg[Symbol.iterator](), x = it.next(); !x.done; x = it.next()) spans.push([x.value.index, x.value.index + x.value.segment.length]);\n")
  val () = $B.bput(b, "        } else {\n")
  val () = $B.bput(b, "          var re = /[^.!?…]+[.!?…]*[\"'”’)\\]]*\\s*/g, m;\n")
  val () = $B.bput(b, "          while ((m = re.exec(text))) spans.push([m.index, m.index + m[0].length]);\n")
  val () = $B.bput(b, "        }\n")
  val () = $B.bput(b, "        function point(i) {\n")
  val () = $B.bput(b, "          for (var k = nodes.length - 1; k >= 0; k--) if (nodes[k].at <= i) return [nodes[k].node, Math.min(i - nodes[k].at, nodes[k].node.data.length)];\n")
  val () = $B.bput(b, "          return [block, 0];\n")
  val () = $B.bput(b, "        }\n")
  val () = $B.bput(b, "        return spans.filter(function (s) { return /\\S/.test(text.slice(s[0], s[1])); }).map(function (s) {\n")
  val () = $B.bput(b, "          var r = document.createRange(), a = point(s[0]), b = point(s[1]);\n")
  val () = $B.bput(b, "          r.setStart(a[0], a[1]); r.setEnd(b[0], b[1]);\n")
  val () = $B.bput(b, "          return { text: text.slice(s[0], s[1]).trim(), range: r };\n")
  val () = $B.bput(b, "        });\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      function shown(box) { return box.isConnected && box.getClientRects().length > 0; }\n")
  val () = $B.bput(b, "      // Where the range starts, against box: -1 before it, 0 in it, 1 after\n")
  val () = $B.bput(b, "      function where(range, box) {\n")
  val () = $B.bput(b, "        var r = range.getClientRects()[0] || range.getBoundingClientRect(), b = box.getBoundingClientRect();\n")
  val () = $B.bput(b, "        if (r.left >= b.right - 1 || r.top >= b.bottom - 1) return 1;\n")
  val () = $B.bput(b, "        if (r.right <= b.left + 1 || r.bottom <= b.top + 1) return -1;\n")
  val () = $B.bput(b, "        return 0;\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      function mark(range) {\n")
  val () = $B.bput(b, "        if (!window.CSS || !CSS.highlights || !window.Highlight) return;\n")
  val () = $B.bput(b, "        if (range) CSS.highlights.set('pwa-spoken', new Highlight(range)); else CSS.highlights.delete('pwa-spoken');\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      function pressed(on) {\n")
  val () = $B.bput(b, "        root.classList.toggle('pwa-speaking', on);\n")
  val () = $B.bput(b, "        document.querySelectorAll('[data-pwa-speak]').forEach(function (e) { e.setAttribute('aria-pressed', on ? 'true' : 'false'); });\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      function awake(on) {\n")
  val () = $B.bput(b, "        if (on && navigator.wakeLock && !wake) navigator.wakeLock.request('screen').then(function (l) { wake = l; }, function () {});\n")
  val () = $B.bput(b, "        if (!on && wake) { wake.release().catch(function () {}); wake = null; }\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      function next(then) {\n")
  val () = $B.bput(b, "        var e = document.querySelector('[data-pwa-speech-next]');\n")
  val () = $B.bput(b, "        if (!e) return then();\n")
  val () = $B.bput(b, "        e.click();\n")
  val () = $B.bput(b, "        setTimeout(then, 300);\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      function stop(keep) {\n")
  val () = $B.bput(b, "        if (!run) return;\n")
  val () = $B.bput(b, "        run.gen++;\n")
  val () = $B.bput(b, "        synth.cancel();\n")
  val () = $B.bput(b, "        mark(null); pressed(false); awake(false);\n")
  val () = $B.bput(b, "        if (keep) run.paused = true; else run = null;\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      // Reads run on from its block bi, sentence si: the page turned on (by\n")
  val () = $B.bput(b, "      // the app's own next button) until the sentence is on it\n")
  val () = $B.bput(b, "      function step(r, tries) {\n")
  val () = $B.bput(b, "        if (run !== r || r.paused) return;\n")
  val () = $B.bput(b, "        var box = r.box;\n")
  val () = $B.bput(b, "        if (!shown(box)) return stop(false);\n")
  val () = $B.bput(b, "        if (r.bi >= r.blocks.length || !r.blocks[r.bi].isConnected) {\n")
  val () = $B.bput(b, "          // the chapter read (or replaced): on to the next one\n")
  val () = $B.bput(b, "          var before = r.blocks[0];\n")
  val () = $B.bput(b, "          if (tries > 2) return stop(false);\n")
  val () = $B.bput(b, "          return next(function () {\n")
  val () = $B.bput(b, "            if (run !== r) return;\n")
  val () = $B.bput(b, "            var bs = blocks(box);\n")
  val () = $B.bput(b, "            if (!bs.length || bs[0] === before) return step(r, tries + 1);\n")
  val () = $B.bput(b, "            r.blocks = bs; r.bi = 0; r.si = 0; r.list = null;\n")
  val () = $B.bput(b, "            step(r, 0);\n")
  val () = $B.bput(b, "          });\n")
  val () = $B.bput(b, "        }\n")
  val () = $B.bput(b, "        if (!r.list) r.list = sentences(r.blocks[r.bi], r.lang);\n")
  val () = $B.bput(b, "        if (r.si >= r.list.length) { r.bi++; r.si = 0; r.list = null; return step(r, 0); }\n")
  val () = $B.bput(b, "        var s = r.list[r.si];\n")
  val () = $B.bput(b, "        if (where(s.range, box) > 0 && tries < 3) return next(function () { step(r, tries + 1); });\n")
  val () = $B.bput(b, "        mark(s.range);\n")
  val () = $B.bput(b, "        var u = new SpeechSynthesisUtterance(s.text), g = r.gen, v = voice(r.lang);\n")
  val () = $B.bput(b, "        u.lang = r.lang; u.rate = rate();\n")
  val () = $B.bput(b, "        if (v) u.voice = v;\n")
  val () = $B.bput(b, "        u.onend = function () { if (run === r && r.gen === g) { r.si++; step(r, 0); } };\n")
  val () = $B.bput(b, "        u.onerror = function (e) { if (run === r && r.gen === g && e.error !== 'interrupted' && e.error !== 'canceled') stop(false); };\n")
  val () = $B.bput(b, "        synth.speak(u);\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      function play(r) {\n")
  val () = $B.bput(b, "        run = r;\n")
  val () = $B.bput(b, "        pressed(true); awake(true);\n")
  val () = $B.bput(b, "        step(r, 0);\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      // A run of box from the sentence holding node at offset (or from the\n")
  val () = $B.bput(b, "      // first sentence on the page)\n")
  val () = $B.bput(b, "      function start(box, node, offset) {\n")
  val () = $B.bput(b, "        var bs = blocks(box), lang = langOf(box), bi = 0, si = 0;\n")
  val () = $B.bput(b, "        if (node) {\n")
  val () = $B.bput(b, "          for (bi = 0; bi < bs.length && !bs[bi].contains(node); bi++);\n")
  val () = $B.bput(b, "          if (bi < bs.length) {\n")
  val () = $B.bput(b, "            // the sentence the point is in, or the first after it\n")
  val () = $B.bput(b, "            var list = sentences(bs[bi], lang);\n")
  val () = $B.bput(b, "            for (si = 0; si < list.length - 1 && list[si + 1].range.comparePoint(node, offset) >= 0; si++);\n")
  val () = $B.bput(b, "          } else bi = 0;\n")
  val () = $B.bput(b, "        } else {\n")
  val () = $B.bput(b, "          while (bi < bs.length) {\n")
  val () = $B.bput(b, "            var l = sentences(bs[bi], lang), k = 0;\n")
  val () = $B.bput(b, "            while (k < l.length && where(l[k].range, box) < 0) k++;\n")
  val () = $B.bput(b, "            if (k < l.length) { si = k; break; }\n")
  val () = $B.bput(b, "            bi++;\n")
  val () = $B.bput(b, "          }\n")
  val () = $B.bput(b, "        }\n")
  val () = $B.bput(b, "        return { box: box, blocks: bs, bi: bi, si: si, list: null, lang: lang, gen: 0, paused: false };\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      document.addEventListener('click', function (e) {\n")
  val () = $B.bput(b, "        var t = e.target && e.target.closest && e.target.closest('[data-pwa-speak],[data-pwa-speak-selection]');\n")
  val () = $B.bput(b, "        if (!t) return;\n")
  val () = $B.bput(b, "        var sel = t.hasAttribute('data-pwa-speak-selection');\n")
  val () = $B.bput(b, "        var box = document.getElementById(t.getAttribute(sel ? 'data-pwa-speak-selection' : 'data-pwa-speak'));\n")
  val () = $B.bput(b, "        if (!box) return;\n")
  val () = $B.bput(b, "        if (sel) {\n")
  val () = $B.bput(b, "          var s = window.getSelection();\n")
  val () = $B.bput(b, "          if (!s || !s.rangeCount || !box.contains(s.getRangeAt(0).startContainer)) return;\n")
  val () = $B.bput(b, "          var a = s.getRangeAt(0);\n")
  val () = $B.bput(b, "          stop(false);\n")
  val () = $B.bput(b, "          return play(start(box, a.startContainer, a.startOffset));\n")
  val () = $B.bput(b, "        }\n")
  val () = $B.bput(b, "        if (run && !run.paused) return stop(true);\n")
  val () = $B.bput(b, "        // go on from where it was paused, if that is still on the page\n")
  val () = $B.bput(b, "        if (run && run.paused && run.box === box && run.list && run.list[run.si] && run.blocks[run.bi].isConnected && where(run.list[run.si].range, box) === 0) {\n")
  val () = $B.bput(b, "          run.paused = false;\n")
  val () = $B.bput(b, "          return play(run);\n")
  val () = $B.bput(b, "        }\n")
  val () = $B.bput(b, "        stop(false);\n")
  val () = $B.bput(b, "        play(start(box, null, 0));\n")
  val () = $B.bput(b, "      }, true);\n")
  val () = $B.bput(b, "      window.addEventListener('pagehide', function () { stop(false); });\n")
  val () = $B.bput(b, "    })();\n")
in $B.bput(b, "  </script>\n") end

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
  (* What the app keeps (IndexedDB) is best effort until it is made
     persistent: under storage pressure the browser may clear it. It is
     asked for once the user has given the app a file (picked or
     dropped), the moment its storage holds something of theirs: Chrome
     grants it by the site's engagement without asking, Firefox asks
     the user, so it is not asked before
     (web.dev/articles/persistent-storage) *)
  val () = $B.bput(b, "  <script>\n")
  val () = $B.bput(b, "    (function () {\n")
  val () = $B.bput(b, "      var s = navigator.storage, root = document.documentElement;\n")
  (* whether it is kept, for the app to say so: pwa-storage-kept, or
     pwa-storage-at-risk; an app of its own (Capacitor) keeps its
     storage as an app's data, which only the user clears *)
  val () = $B.bput(b, "      function mark(kept) {\n")
  val () = $B.bput(b, "        root.classList.toggle('pwa-storage-kept', kept);\n")
  val () = $B.bput(b, "        root.classList.toggle('pwa-storage-at-risk', !kept);\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      var native = window.Capacitor && Capacitor.isNativePlatform && Capacitor.isNativePlatform();\n")
  val () = $B.bput(b, "      if (native) return mark(true);\n")
  val () = $B.bput(b, "      if (!s || !s.persist || !s.persisted) return;\n")
  val () = $B.bput(b, "      s.persisted().then(mark).catch(function () {});\n")
  val () = $B.bput(b, "      var asked = false;\n")
  val () = $B.bput(b, "      function given(e) {\n")
  val () = $B.bput(b, "        var f = e.type === 'drop' ? e.dataTransfer && e.dataTransfer.files\n")
  val () = $B.bput(b, "          : e.target && e.target.type === 'file' && e.target.files;\n")
  val () = $B.bput(b, "        if (asked || !f || !f.length) return;\n")
  val () = $B.bput(b, "        asked = true;\n")
  val () = $B.bput(b, "        s.persisted().then(function (p) { return p || s.persist(); }).then(mark).catch(function () {});\n")
  val () = $B.bput(b, "      }\n")
  val () = $B.bput(b, "      document.addEventListener('change', given, true);\n")
  val () = $B.bput(b, "      document.addEventListener('drop', given, true);\n")
  val () = $B.bput(b, "    })();\n")
  val () = $B.bput(b, "  </script>\n")
  (* Installing. The root element is marked pwa-can-install while the
     browser offers to install the app (beforeinstallprompt: Chrome and
     Edge; its own mini-infobar is kept back, as for an app's own
     install button), and a click on an element marked data-pwa-install
     asks it to; the app shows that element only under the mark. On iOS
     Safari outside the Home Screen (navigator.standalone false, which
     only iOS defines) there is no such prompt: the root is marked
     pwa-ios-browser, for the app to say how to add it there
     (web.dev/articles/promote-install, firt.dev/notes/pwa-ios) *)
  val () = $B.bput(b, "  <script>\n")
  val () = $B.bput(b, "    (function () {\n")
  val () = $B.bput(b, "      var root = document.documentElement, offer = null;\n")
  (* night by the local clock, 22:00 to 07:00 (iOS Night Shift's
     default schedule), which an app's wasm cannot tell (its time is
     UTC): pwa-night, checked each minute *)
  val () = $B.bput(b, "      function night() { var h = new Date().getHours(); root.classList.toggle('pwa-night', h >= 22 || h < 7); }\n")
  val () = $B.bput(b, "      night(); setInterval(night, 60000);\n")
  val () = $B.bput(b, "      document.addEventListener('visibilitychange', night);\n")
  val () = $B.bput(b, "      if (navigator.standalone === false) root.classList.add('pwa-ios-browser');\n")
  val () = $B.bput(b, "      window.addEventListener('beforeinstallprompt', function (e) {\n")
  val () = $B.bput(b, "        e.preventDefault(); offer = e; root.classList.add('pwa-can-install');\n")
  val () = $B.bput(b, "      });\n")
  val () = $B.bput(b, "      window.addEventListener('appinstalled', function () {\n")
  val () = $B.bput(b, "        offer = null; root.classList.remove('pwa-can-install');\n")
  val () = $B.bput(b, "      });\n")
  val () = $B.bput(b, "      document.addEventListener('click', function (e) {\n")
  val () = $B.bput(b, "        var t = e.target && e.target.closest && e.target.closest('[data-pwa-install]');\n")
  val () = $B.bput(b, "        if (!t || !offer) return;\n")
  val () = $B.bput(b, "        var o = offer; offer = null; root.classList.remove('pwa-can-install');\n")
  val () = $B.bput(b, "        o.prompt();\n")
  val () = $B.bput(b, "      }, true);\n")
  val () = $B.bput(b, "    })();\n")
  val () = $B.bput(b, "  </script>\n")
  val () = _speech_script(b)
  val () = _share_script(b)
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
  (* the page's sharing, where the WebView has no navigator.share *)
  val () = $B.bput(b, "    \"@capacitor/share\": \"^8.0.2\"\n")
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

implement build_android_script (b, web_dir) = let
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
  val () = $B.bput(b, "# the app's activity, which hands the files it is opened with and\n")
  val () = $B.bput(b, "# shared to the page, and its intent filters\n")
  val () = $B.bput(b, "cp MainActivity.java \"$(find android/app/src/main/java -name MainActivity.java)\"\n")
  val () = $B.bput(b, "m=android/app/src/main/AndroidManifest.xml\n")
  val () = $B.bput(b, "awk 'FNR==NR { f = f $0 \"\\n\"; next } /<\\/activity>/ && !d { printf \"%s\", f; d = 1 } { print }' intent-filters.xml \"$m\" > \"$m.new\"\n")
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
  val () = $B.bput(b, "npx cap sync android\n")
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
  val () = $B.bput(b, "public class MainActivity extends BridgeActivity {\n")
  val () = $B.bput(b, "    private static final String TAG = \"BatsFiles\";\n")
  val () = $B.bput(b, "    private final Handler handler = new Handler(Looper.getMainLooper());\n")
  val () = $B.bput(b, "\n")
  val () = $B.bput(b, "    @Override\n")
  val () = $B.bput(b, "    public void onCreate(Bundle savedInstanceState) {\n")
  val () = $B.bput(b, "        super.onCreate(savedInstanceState);\n")
  val () = $B.bput(b, "        if (savedInstanceState == null) {\n")
  val () = $B.bput(b, "            File[] old = incoming().listFiles();\n")
  val () = $B.bput(b, "            if (old != null) for (File f : old) f.delete();\n")
  val () = $B.bput(b, "            handle(getIntent());\n")
  val () = $B.bput(b, "        }\n")
  val () = $B.bput(b, "    }\n")
  val () = $B.bput(b, "\n")
  val () = $B.bput(b, "    @Override\n")
  val () = $B.bput(b, "    protected void onNewIntent(Intent intent) {\n")
  val () = $B.bput(b, "        super.onNewIntent(intent);\n")
  val () = $B.bput(b, "        setIntent(intent);\n")
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
  val () = $B.bput(b, "        final String js = \"(function(){var t=document.activeElement||document.body;\"\n")
  val () = $B.bput(b, "            + \"return t.dispatchEvent(new KeyboardEvent('keydown',{key:'\"\n")
  val () = $B.bput(b, "            + (up ? \"AudioVolumeUp\" : \"AudioVolumeDown\") + \"',bubbles:true,cancelable:true}));})()\";\n")
  val () = $B.bput(b, "        bridge.getWebView().evaluateJavascript(js, r -> {\n")
  val () = $B.bput(b, "            boolean taken = \"false\".equals(r);\n")
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
  val () = $B.bput(b, "            deliver(intent.getData());\n")
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
  val () = $B.bput(b, "                final String js = \"(function(){if(!globalThis.batsFetchExternal)return false;\"\n")
  val () = $B.bput(b, "                    + \"globalThis.batsFetchExternal(\" + JSONObject.quote(\"/_capacitor_file_\" + out.getAbsolutePath())\n")
  val () = $B.bput(b, "                    + \",\" + JSONObject.quote(name) + \");return true;})()\";\n")
  val () = $B.bput(b, "                Log.i(TAG, \"copied \" + out.length() + \" bytes to \" + out);\n")
  val () = $B.bput(b, "                handler.post(() -> hand(js, 240));\n")
  val () = $B.bput(b, "            } catch (Exception e) {\n")
  val () = $B.bput(b, "                // a file that cannot be read is not handed over\n")
  val () = $B.bput(b, "                Log.w(TAG, \"cannot read \" + uri, e);\n")
  val () = $B.bput(b, "            }\n")
  val () = $B.bput(b, "        }).start();\n")
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
  val () = $B.bput(b, "# <file> <type> <text>, then shares the file with the app and waits\n")
  val () = $B.bput(b, "# for that text too.\n")
  val () = $B.bput(b, "set -eu\n")
  val () = $B.bput(b, "APP_ID='")
  val () = $B.bput(b, app_id)
  val () = $B.bput(b, "'\n")
  val () = $B.bput(b, "APK=$1\nTEXT=$2\nOUT=$3\n")
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
  val () = $B.bput(b, "adb shell monkey -p \"$APP_ID\" -c android.intent.category.LAUNCHER 1 >/dev/null\n")
  val () = $B.bput(b, "found=0\n")
  val () = $B.bput(b, "for _ in $(seq 60); do\n")
  val () = $B.bput(b, "  sleep 2\n")
  val () = $B.bput(b, "  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || continue\n")
  val () = $B.bput(b, "  adb shell cat /sdcard/ui.xml > \"$OUT/ui.xml\" || continue\n")
  val () = $B.bput(b, "  if grep -qF \"$TEXT\" \"$OUT/ui.xml\"; then found=1; break; fi\n")
  val () = $B.bput(b, "done\n")
  val () = $B.bput(b, "# A volume key is offered to the page first (the activity logs whether\n")
  val () = $B.bput(b, "# the page took it); it must reach the page, and not crash the app\n")
  val () = $B.bput(b, "volume=0\n")
  val () = $B.bput(b, "if [ $found = 1 ]; then\n")
  val () = $B.bput(b, "  adb shell input keyevent KEYCODE_VOLUME_DOWN\n")
  val () = $B.bput(b, "  for _ in $(seq 10); do\n")
  val () = $B.bput(b, "    sleep 1\n")
  val () = $B.bput(b, "    if adb logcat -d | grep -q \"volume key: the page\"; then volume=1; break; fi\n")
  val () = $B.bput(b, "  done\n")
  val () = $B.bput(b, "fi\n")
  val () = $B.bput(b, "# Sharing a file with the app: it is put in the app's cache (adb as\n")
  val () = $B.bput(b, "# root, on an emulator) and handed to it with SEND, as another app\n")
  val () = $B.bput(b, "# would share it\n")
  val () = $B.bput(b, "if [ $found = 1 ] && [ $# -ge 6 ]; then\n")
  val () = $B.bput(b, "  TEXT=$6\n")
  val () = $B.bput(b, "  DEST=\"/data/data/$APP_ID/cache/smoke-share\"\n")
  val () = $B.bput(b, "  adb root >/dev/null\n")
  val () = $B.bput(b, "  adb wait-for-device\n")
  val () = $B.bput(b, "  adb push \"$4\" /data/local/tmp/smoke-share >/dev/null\n")
  val () = $B.bput(b, "  OWNER=$(adb shell stat -c %u \"/data/data/$APP_ID\" | tr -d '\\r')\n")
  val () = $B.bput(b, "  adb shell \"cp /data/local/tmp/smoke-share $DEST && chown $OWNER:$OWNER $DEST && restorecon $DEST\"\n")
  val () = $B.bput(b, "  adb shell am start -a android.intent.action.SEND -t \"$5\" --eu android.intent.extra.STREAM \"file://$DEST\" -n \"$APP_ID/.MainActivity\" >/dev/null\n")
  val () = $B.bput(b, "  found=0\n")
  val () = $B.bput(b, "  for _ in $(seq 60); do\n")
  val () = $B.bput(b, "    sleep 2\n")
  val () = $B.bput(b, "    adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || continue\n")
  val () = $B.bput(b, "    adb shell cat /sdcard/ui.xml > \"$OUT/ui.xml\" || continue\n")
  val () = $B.bput(b, "    if grep -qF \"$TEXT\" \"$OUT/ui.xml\"; then found=1; break; fi\n")
  val () = $B.bput(b, "  done\n")
  val () = $B.bput(b, "fi\n")
  val () = $B.bput(b, "adb exec-out screencap -p > \"$OUT/screenshot.png\"\n")
  val () = $B.bput(b, "adb logcat -d > \"$OUT/logcat.txt\"\n")
  val () = $B.bput(b, "status=0\n")
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
  val () = $B.bput(b, "if [ $found = 1 ] && [ $volume = 0 ]; then\n")
  val () = $B.bput(b, "  echo \"A volume key never reached the page\"; status=1\n")
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
  var sh_b = $B.create()
  val () = build_android_script(sh_b, web_dir)
  val () = _write_mode(project_dir, "build-android.sh", sh_b, 493)
  var st_b = $B.create()
  val () = build_smoke_test_script(st_b, app_id)
in _write_mode(project_dir, "smoke-test.sh", st_b, 493) end
