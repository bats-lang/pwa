(* test_run -- gen-pwa test: runs an app's Playwright suite against its
   built PWA (bats-lang/pwa#82). Tooling for the app's tests: nothing
   here is part of what pwa generates or of what the app runs.

   gen-pwa test [--timings <dir>] [-- <playwright args>]

   1. A slot of the machine's lock: flock on one of PWA_TEST_SLOTS
      (default 1) files in PWA_TEST_LOCK_DIR (default ~/.cache/pwa-test),
      said when the run waits for one. The kernel releases it when the
      run ends, however it ends, and what the run starts inherits it.
   2. The browsers' location (PLAYWRIGHT_BROWSERS_PATH, else Playwright's
      default) must hold the headless Chromium the project's Playwright
      expects; nothing is downloaded, and a missing or older one is said
      with both revisions.
   3. The workers: half the cores (Playwright's default) divided by the
      slots, at least 1.
   4. The tests tagged @serial run alone on one worker, then the others
      on those workers; a --grep or --workers of the caller's makes it
      one run, as given.
   5. Each Playwright run is started by a keeper (node -e: Bats has no
      sockets; the browser check in 2 reads browsers.json with node too) that serves dist/pwa on 127.0.0.1 at a port the kernel
      picks, hands Playwright PWA_TEST_BASE_URL, and stops Playwright's
      process group, and itself with its server, when its stdin (a pipe
      from this process) closes: when gen-pwa ends, however it ends.
   6. --timings <dir> adds Playwright's JSON reporter to each run, into
      <dir>/serial.json and <dir>/parallel.json.

   PWA_TEST_PLAYWRIGHT names the Playwright to run (default the
   project's node_modules/.bin/playwright). *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use env as E
#use file as F
#use list as L
#use process as P
#use result as R

(* ============================================================
   Builders and arguments
   ============================================================ *)

fn _put (out: !$B.builder_v >> $B.builder_v, v: int): void =
  if $B.length(out) < 524288 then $B.put_char(out, $AR.low_byte(v)) else ()

fn _bput {sn:nat} (out: !$B.builder_v >> $B.builder_v, s: string sn): void = let
  fun loop {sl:nat}{i:nat | i <= sl} .<sl - i>.
    (out: !$B.builder_v >> $B.builder_v, s: string sl, n: int sl, i: int i): void =
    if i >= n then ()
    else let
      val () = _put(out, char2int0(string_get_at(s, i)))
    in loop(out, s, n, i + 1) end
in loop(out, s, g1u2i(string1_length(s)), 0) end

(* v >= 0 in decimal *)
fun _put_int {v:nat} .<v>. (out: !$B.builder_v >> $B.builder_v, v: int v): void =
  if v < 10 then _put(out, 48 + v)
  else let
    val () = _put_int(out, v / 10)
  in _put(out, 48 + (v - (v / 10) * 10)) end

fn _put_nat (out: !$B.builder_v >> $B.builder_v, v: int): void = let
  val v1 = g1ofg0(v)
in if v1 >= 0 then _put_int(out, v1) else _put(out, 48) end

(* b[i, k) appended to out *)
fun _put_range {l:agz}{n:pos}{i:nat} .<max(n - i, 0)>.
  (b: !$A.borrow(byte, l, n), i: int i, k: int, n: int n, out: !$B.builder_v >> $B.builder_v): void =
  if i >= k then ()
  else if i >= n then ()
  else let
    val () = _put(out, byte2int0($A.read<byte>(b, i)))
  in _put_range(b, i + 1, k, n, out) end

fn _nat (x: int): [n:nat] int n = let
  val y = g1ofg0(x)
in if y >= 0 then y else 0 end

fn _arg (b: $B.builder_v): $P.arg_entry = let
  val @(a, k) = $B.to_arr(b)
in @(a, k) end

fn _arg_s {sn:nat} (s: string sn): $P.arg_entry = let
  var b : $B.builder_v = $B.create()
  val () = _bput(b, s)
in _arg(b) end

fun _rev {n:nat} .<n>.
  (xs: $L.list_vt($P.arg_entry, n), acc: $L.listv($P.arg_entry)): $L.listv($P.arg_entry) =
  case+ xs of
  | ~$L.list_vt_nil() => acc
  | ~$L.list_vt_cons(x, tl) => _rev(tl, $L.list_vt_cons(x, acc))

(* b's bytes to stderr; b consumed *)
fn _say (b: $B.builder_v): void = let
  val @(a, k) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(a)
  fun loop {l:agz}{i:nat} .<max(524288 - i, 0)>.
    (bv: !$A.borrow(byte, l, 524288), i: int i, k: int): void =
    if i >= k then ()
    else if i >= 524288 then ()
    else let
      val () = prerr_char(int2char0(byte2int0($A.read<byte>(bv, i))))
    in loop(bv, i + 1, k) end
  val () = loop(bv, 0, k)
  val () = $A.drop<byte>(fz, bv)
in $A.free<byte>($A.thaw<byte>(fz)) end

(* ============================================================
   The environment, the arguments, and sh
   ============================================================ *)

fun _fill {sn:nat}{l:agz}{i:nat | i <= sn} .<sn - i>.
  (a: !$A.arr(byte, l, sn), s: string sn, n: int sn, i: int i): void =
  if i >= n then ()
  else let
    val () = $A.set<byte>(a, i, int2byte0(char2int0(string_get_at(s, i))))
  in _fill(a, s, n, i + 1) end

(* The variable name's value appended to out: whether it is set and not
   empty *)
fn _env {sn:pos | sn < 1048576} (name: string sn, out: !$B.builder_v >> $B.builder_v): bool = let
  val n = g1u2i(string1_length(name))
  val a = $A.alloc<byte>(n)
  val () = _fill(a, name, n, 0)
  val @(fz_a, bv_a) = $A.freeze<byte>(a)
  val buf = $A.alloc<byte>(4096)
  val got = $E.get(bv_a, n, buf, 4096)
  val () = $A.drop<byte>(fz_a, bv_a)
  val () = $A.free<byte>($A.thaw<byte>(fz_a))
  val k = (case+ got of | ~$R.some(k) => k | ~$R.none() => 0): int
  val @(fz_b, bv_b) = $A.freeze<byte>(buf)
  val () = _put_range(bv_b, 0, k, 4096, out)
  val () = $A.drop<byte>(fz_b, bv_b)
  val () = $A.free<byte>($A.thaw<byte>(fz_b))
in k > 0 end

(* The process's arguments, NUL-separated, into buf: their length *)
fn _args {l:agz} (buf: !$A.arr(byte, l, 4096)): int =
  case+ $E.args_read(buf, 4096) of
  | ~$R.some(k) => k
  | ~$R.none() => 0

(* Where the argument starting at i ends (its NUL), within k *)
fun _arg_end {l:agz}{i:nat} .<max(4096 - i, 0)>.
  (b: !$A.borrow(byte, l, 4096), i: int i, k: int): int =
  if i >= k then k
  else if i >= 4096 then i
  else if byte2int0($A.read<byte>(b, i)) = 0 then i
  else _arg_end(b, i + 1, k)

(* Whether b[s, e) is exactly s2 (whole: true), or starts with it *)
fn _is {sn:nat}{l:agz} (b: !$A.borrow(byte, l, 4096), s: int, e: int, lit: string sn, whole: bool): bool = let
  val n = g1u2i(string1_length(lit))
  fun loop {sl:nat}{j:nat | j <= sl} .<sl - j>.
    (b: !$A.borrow(byte, l, 4096), s: int, e: int, lit: string sl, n: int sl, j: int j): bool =
    if j >= n then true
    else let
      val at = g1ofg0(s + j)
    in
      if at < 0 then false
      else if at >= 4096 then false
      else if s + j >= e then false
      else if byte2int0($A.read<byte>(b, at)) <> char2int0(string_get_at(lit, j)) then false
      else loop(b, s, e, lit, n, j + 1)
    end
in
  if whole then (e - s = n && loop(b, s, e, lit, n, 0))
  else (e - s >= n && loop(b, s, e, lit, n, 0))
end

(* The program called name, looked up on PATH as execvp does, as a
   NUL-terminated path *)
fn _program {sn:nat} (name: string sn): [l:agz] $A.arr(byte, l, 524288) = let
  var b : $B.builder_v = $B.create()
  val () = _bput(b, name)
  val () = _put(b, 0)
  val @(a, _) = $B.to_arr(b)
in a end

(* b[i, k) up to its first newline appended to out *)
fun _put_line {l:agz}{i:nat} .<max(4096 - i, 0)>.
  (b: !$A.borrow(byte, l, 4096), i: int i, k: int, out: !$B.builder_v >> $B.builder_v): void =
  if i >= k then ()
  else if i >= 4096 then ()
  else let
    val c = byte2int0($A.read<byte>(b, i))
  in
    if c = 10 then ()
    else let val () = _put(out, c) in _put_line(b, i + 1, k, out) end
  end

(* sh -c script with args as $1, $2, ...: the first line of its stdout
   appended to out, and its status (-1 when sh could not be run). What
   it writes to stderr is shown. *)
fn _sh {sn:nat}
  (script: string sn, args: $L.listv($P.arg_entry), out: !$B.builder_v >> $B.builder_v): int = let
  val x = _program("sh")
  val @(fz_x, bv_x) = $A.freeze<byte>(x)
  val argv = $L.list_vt_cons(_arg_s("sh"), $L.list_vt_cons(_arg_s("-c"),
    $L.list_vt_cons(_arg_s(script), $L.list_vt_cons(_arg_s("sh"), args))))
  val buf = $A.alloc<byte>(4096)
  val rc = (case+ $P.spawn_inherit_env(bv_x, argv, $P.dev_null(), $P.pipe_new(), $P.inherit()) of
    | ~$R.ok(sp) => let
        val+ ~$P.spawn_pipes_mk(child, sin_p, sout_p, serr_p) = sp
        val () = $P.pipe_end_close(sin_p)
        val () = $P.pipe_end_close(serr_p)
        val+ ~$P.pipe_fd(out_fd) = sout_p
        val k = (case+ $F.file_read(out_fd, buf, 4096) of
          | ~$R.ok(n) => n | ~$R.err(_) => 0): int
        val () = $R.discard<int><$F.io_error>($F.file_close(out_fd))
        val ec = (case+ $P.child_wait(child) of | ~$R.ok(n) => n | ~$R.err(_) => ~1): int
        val @(fz_b, bv_b) = $A.freeze<byte>(buf)
        val () = _put_line(bv_b, 0, k, out)
        val () = $A.drop<byte>(fz_b, bv_b)
        val () = $A.free<byte>($A.thaw<byte>(fz_b))
      in ec end
    | ~$R.err(_) => let
        val () = $A.free<byte>(buf)
      in ~1 end): int
  val () = $A.drop<byte>(fz_x, bv_x)
  val () = $A.free<byte>($A.thaw<byte>(fz_x))
in rc end

(* The number b starts with, or ~1 when it starts with none *)
fn _number_of (b: $B.builder_v): int = let
  val @(a, k) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(a)
  fun loop {l:agz}{i:nat} .<max(524288 - i, 0)>.
    (bv: !$A.borrow(byte, l, 524288), i: int i, k: int, acc: int): int =
    if i >= k then acc
    else if i >= 524288 then acc
    else let
      val c = byte2int0($A.read<byte>(bv, i))
    in
      if c >= 48 && c <= 57 then
        (if acc > 100000 then acc
         else let
           val base = (if acc < 0 then 0 else acc): int
         in loop(bv, i + 1, k, base * 10 + (c - 48)) end)
      else acc
    end
  val r = loop(bv, 0, k, ~1)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in r end

(* ============================================================
   1. The machine's lock
   ============================================================ *)

(* PWA_TEST_SLOTS, 1 to 64: how many runs the machine takes at once *)
fn _slots (): int = let
  var b : $B.builder_v = $B.create()
  val set = _env("PWA_TEST_SLOTS", b)
  val n = _number_of(b)
in if ~set then 1 else if n < 1 then 1 else if n > 64 then 64 else n end

(* The lock's directory appended to out: PWA_TEST_LOCK_DIR, else
   ~/.cache/pwa-test *)
fn _lock_dir (out: !$B.builder_v >> $B.builder_v): void = let
  var d : $B.builder_v = $B.create()
  val set = _env("PWA_TEST_LOCK_DIR", d)
  val @(a, k) = $B.to_arr(d)
  val @(fz, bv) = $A.freeze<byte>(a)
  val () = _put_range(bv, 0, k, 524288, out)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
  var h : $B.builder_v = $B.create()
  val home = (if set then false else _env("HOME", h)): bool
  val @(ha, hk) = $B.to_arr(h)
  val @(fz_h, bv_h) = $A.freeze<byte>(ha)
  val () = _put_range(bv_h, 0, (if home then hk else 0), 524288, out)
  val () = $A.drop<byte>(fz_h, bv_h)
  val () = $A.free<byte>($A.thaw<byte>(fz_h))
in if set then _bput(out, "") else _bput(out, "/.cache/pwa-test") end

(* A slot of the lock, or why the run goes on without one *)
datavtype slot =
  | SlotHeld of $F.fd
  | NoLockDir        (* the lock's directory cannot be made *)
  | NoLockFile       (* a slot's file cannot be opened *)
  | LockUnsupported  (* its file system has no locks *)

(* What trying slot i without waiting found *)
datavtype try_found =
  | Taken of $F.fd
  | Busy
  | Unopenable   (* the slot's file cannot be opened *)
  | Unlockable   (* it opens, but cannot be locked *)

fn _slot_open (i: int): $R.result($F.fd, $F.io_error) = let
  var p : $B.builder_v = $B.create()
  val () = _lock_dir(p)
  val () = _bput(p, "/slot-")
  val () = _put_nat(p, i)
  val () = _bput(p, ".lock")
  val () = _put(p, 0)
  val @(pa, _) = $B.to_arr(p)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  val r = $F.file_open(bv_p, 524288, $F.ReadWrite(), $F.CreateOrOpen(), 420)
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in r end

fn _slot_try (i: int, wait: $F.lock_wait): try_found =
  case+ _slot_open(i) of
  | ~$R.err(_) => Unopenable()
  | ~$R.ok(fd) =>
    (case+ $F.fd_lock(fd, $F.LockExclusive(), wait) of
    | ~$R.ok(_) => Taken(fd)
    | ~$R.err(e) => let
        val busy = (case+ e of $F.WouldBlock() => true | _ => false): bool
        val () = $R.discard<int><$F.io_error>($F.file_close(fd))
      in if busy then Busy() else Unlockable() end)

(* The first free slot of i to n - 1, without waiting *)
fun _slot_free {i,n:nat} .<max(n - i, 0)>. (i: int i, n: int n): try_found =
  if i >= n then Busy()
  else (case+ _slot_try(i, $F.LockFailsAtOnce()) of
    | ~Taken(fd) => Taken(fd)
    | ~Busy() => _slot_free(i + 1, n)
    | ~Unopenable() => Unopenable()
    | ~Unlockable() => Unlockable())

(* Takes a slot: the first free one, else, said, slot 0 once it is free
   (with more than one slot, a run that waits waits for slot 0, though
   another may be freed first) *)
fn _lock (): slot = let
  var d : $B.builder_v = $B.create()
  val () = _lock_dir(d)
  var ignored : $B.builder_v = $B.create()
  val made = _sh("mkdir -p \"$1\"", $L.list_vt_cons(_arg(d), $L.list_vt_nil()), ignored)
  val () = $B.builder_free(ignored)
  val n = g1ofg0(_slots())
in
  if made <> 0 then NoLockDir()
  else if n < 1 then NoLockDir()
  else (case+ _slot_free(0, n) of
    | ~Taken(fd) => SlotHeld(fd)
    | ~Unopenable() => NoLockFile()
    | ~Unlockable() => LockUnsupported()
    | ~Busy() => let
        var m : $B.builder_v = $B.create()
        val () = _bput(m, "gen-pwa test: waiting for another gen-pwa test (")
        val () = _put_nat(m, n)
        val () = _bput(m, " at once, PWA_TEST_SLOTS)\n")
        val () = _say(m)
      in
        case+ _slot_try(0, $F.LockWaits()) of
        | ~Taken(fd) => SlotHeld(fd)
        | ~Busy() => LockUnsupported()
        | ~Unopenable() => NoLockFile()
        | ~Unlockable() => LockUnsupported()
      end)
end

fn _unlock (s: slot): void =
  case+ s of
  | ~SlotHeld(fd) => $R.discard<int><$F.io_error>($F.file_close(fd))
  | ~NoLockDir() => ()
  | ~NoLockFile() => ()
  | ~LockUnsupported() => ()

(* ============================================================
   2. Playwright and its browsers
   ============================================================ *)

(* What the browsers' location holds against what the project's
   Playwright expects *)
datatype browsers =
  | BrowsersReady
  | BrowsersOlder      (* only older revisions than Playwright expects *)
  | BrowsersMissing    (* the revision expected, or any older, is not there *)
  | NoPlaywrightCore   (* the project has no playwright-core to ask *)
  | NoNode             (* node cannot be run *)

(* The browsers' location appended to out: PLAYWRIGHT_BROWSERS_PATH, else
   Playwright's default on macOS, else elsewhere *)
fn _browsers_dir (out: !$B.builder_v >> $B.builder_v): void = let
  var b : $B.builder_v = $B.create()
  val set = _env("PLAYWRIGHT_BROWSERS_PATH", b)
  val @(a, k) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(a)
  val () = _put_range(bv, 0, k, 524288, out)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
  var dflt : $B.builder_v = $B.create()
  val _ = (if set then 0
    else _sh("if [ -d \"$HOME/Library/Caches/ms-playwright\" ]; then echo \"$HOME/Library/Caches/ms-playwright\"; else echo \"$HOME/.cache/ms-playwright\"; fi",
      $L.list_vt_nil(), dflt)): int
  val @(da, dk) = $B.to_arr(dflt)
  val @(fz_d, bv_d) = $A.freeze<byte>(da)
  val () = _put_range(bv_d, 0, dk, 524288, out)
  val () = $A.drop<byte>(fz_d, bv_d)
in $A.free<byte>($A.thaw<byte>(fz_d)) end

(* The project's Playwright's version and the headless Chromium revision
   it expects, then the revisions the location has, then which: 0 ready,
   3 only older ones, 4 none (missing), 5 no playwright-core, 127 no node.
   Read by node from playwright-core's browsers.json: nothing is run of
   Playwright's and nothing is downloaded. *)
#define BROWSER_CHECK "b=$1; v=$(node -e 'const p=require(\"path\"),f=require(\"fs\");try{const d=p.dirname(require.resolve(\"playwright-core/package.json\",{paths:[process.cwd()]}));const j=JSON.parse(f.readFileSync(p.join(d,\"browsers.json\"),\"utf8\"));const s=j.browsers.find(x=>x.name===\"chromium-headless-shell\");console.log(require(p.join(d,\"package.json\")).version+\" \"+s.revision)}catch(e){process.exit(5)}'); rc=$?; [ $rc = 0 ] || exit $rc; set -- $v; ver=$1; rev=$2; [ -d \"$b/chromium_headless_shell-$rev\" ] && { echo \"$ver $rev\"; exit 0; }; older=; newer=; for d in \"$b\"/chromium_headless_shell-*; do [ -d \"$d\" ] || continue; r=${d##*-}; case $r in *[!0-9]*|'') continue ;; esac; if [ \"$r\" -lt \"$rev\" ]; then older=\"$older $r\"; else newer=\"$newer $r\"; fi; done; echo \"Playwright $ver expects chromium_headless_shell-$rev; the location has:${older:- no older revision}${newer:+, newer:$newer}\"; [ -n \"$older\" ] && [ -z \"$newer\" ] && exit 3; exit 4"

(* What the location holds, and what the check said of it *)
fn _browsers (): @(browsers, $B.builder_v) = let
  var dir : $B.builder_v = $B.create()
  val () = _browsers_dir(dir)
  var said : $B.builder_v = $B.create()
  val rc = _sh(BROWSER_CHECK, $L.list_vt_cons(_arg(dir), $L.list_vt_nil()), said)
  val found = (if rc = 0 then BrowsersReady()
    else if rc = 3 then BrowsersOlder()
    else if rc = 4 then BrowsersMissing()
    else if rc = 5 then NoPlaywrightCore()
    else NoNode()): browsers
in @(found, said) end

(* The Playwright to run appended to out: PWA_TEST_PLAYWRIGHT, else the
   project's own; whether it was named *)
fn _playwright (out: !$B.builder_v >> $B.builder_v): bool = let
  var b : $B.builder_v = $B.create()
  val named = _env("PWA_TEST_PLAYWRIGHT", b)
  val @(a, k) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(a)
  val () = _put_range(bv, 0, k, 524288, out)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
  val () = (if named then _bput(out, "") else _bput(out, "node_modules/.bin/playwright"))
in named end

(* ============================================================
   2a. The Playwright version (bats-lang/pwa#92)
   ============================================================ *)

(* The least Playwright gen-pwa test runs. Before it, the fake clock
   (page.clock) can set the time back: its real-time sync starts a
   _runTo(now) that yields to the event loop, page.clock.fastForward
   jumps meanwhile, and the older _runTo then calls _advanceNow with its
   old target, undoing the jump (a test that counts minutes lost one in
   about five runs on 1.56.1, none in 40 on 1.58.2: quire#352, quire#366).
   From 1.57.0 on _advanceNow starts with
   `if (this._now.ticks > to) return`, a target in the past is ignored
   (read from playwright-core/lib/generated/clockSource.js of 1.56.1,
   1.57.0 and 1.58.0); the release notes of 1.57 and 1.58 do not mention
   it. 1.58 is the floor because it is the oldest the suites using
   gen-pwa test are run on. A constant, not a setting of the app: an app
   that needs a newer Playwright says so in its package.json, which npm
   enforces when it installs (and e2e-setup's playwright-minimum checks
   in CI), and a setting that could only raise this floor would be a path
   to prove for no gain. *)
#define PLAYWRIGHT_MIN_MAJOR 1
#define PLAYWRIGHT_MIN_MINOR 58
#define PLAYWRIGHT_MIN_PATCH 0

(* A Playwright version as its package.json writes it: major.minor.patch
   and, optionally, a pre-release or build suffix (- or +, then
   letters, digits, dots, hyphens and plus signs). Each number has 1 to 6
   digits. The bool is whether it is a release: no suffix, or only build
   metadata (+), which semver does not order by; a - suffix is a pre-release. *)
datavtype version_read =
  | VersionRead of (int, int, int, bool)
  | VersionUnreadable

datatype support =
  | PlaywrightSupported
  | PlaywrightTooOld
  | PlaywrightUnreadable

(* b[i], or ~1 outside b[0, k) *)
fn _at {l:agz}{n:pos} (b: !$A.borrow(byte, l, n), n: int n, k: int, i: int): int = let
  val j = g1ofg0(i)
in
  if j < 0 then ~1
  else if j >= n then ~1
  else if j >= k then ~1
  else byte2int0($A.read<byte>(b, j))
end

(* The decimal digits of b[i, k) from i: their value, where they end, and
   how many (7 when there are more than 6: the number is refused) *)
fun _digits {l:agz}{n:pos}{i:nat} .<max(n - i, 0)>.
  (b: !$A.borrow(byte, l, n), n: int n, k: int, i: int i, acc: int, count: int): @(int, int, int) =
  if i >= k then @(acc, i, count)
  else if i >= n then @(acc, i, count)
  else let
    val c = byte2int0($A.read<byte>(b, i))
  in
    if c >= 48 && c <= 57 then
      (if count >= 6 then @(acc, i, 7)
       else _digits(b, n, k, i + 1, acc * 10 + (c - 48), count + 1))
    else @(acc, i, count)
  end

fn _digits_from {l:agz}{n:pos} (b: !$A.borrow(byte, l, n), n: int n, k: int, i: int): @(int, int, int) = let
  val j = g1ofg0(i)
in if j < 0 then @(0, i, 0) else _digits(b, n, k, j, 0, 0) end

(* Whether b[i, k) is one or more letters, digits, dots, hyphens and
   plus signs, and nothing else *)
fun _suffix_ok {l:agz}{n:pos}{i:nat} .<max(n - i, 0)>.
  (b: !$A.borrow(byte, l, n), n: int n, k: int, i: int i, seen: bool): bool =
  if i >= k then seen
  else if i >= n then seen
  else let
    val c = byte2int0($A.read<byte>(b, i))
    val word = ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
      || c = 46 || c = 45 || c = 43): bool
  in if word then _suffix_ok(b, n, k, i + 1, true) else false end

fn _suffix_from {l:agz}{n:pos} (b: !$A.borrow(byte, l, n), n: int n, k: int, i: int): bool = let
  val j = g1ofg0(i)
in if j < 0 then false else _suffix_ok(b, n, k, j, false) end

(* b[0, k) as a version; total: every text is one or the other *)
fn version_read_of {l:agz}{n:pos} (b: !$A.borrow(byte, l, n), n: int n, k: int): version_read = let
  val @(major, e1, c1) = _digits_from(b, n, k, 0)
  val dot1 = (c1 >= 1 && c1 <= 6 && _at(b, n, k, e1) = 46): bool
  val @(minor, e2, c2) = _digits_from(b, n, k, e1 + 1)
  val dot2 = (dot1 && c2 >= 1 && c2 <= 6 && _at(b, n, k, e2) = 46): bool
  val @(patch, e3, c3) = _digits_from(b, n, k, e2 + 1)
  val numbers = (dot2 && c3 >= 1 && c3 <= 6): bool
  val after = _at(b, n, k, e3)
  val tail = (if after = ~1 then true
    else if after = 45 || after = 43 then _suffix_from(b, n, k, e3 + 1)
    else false): bool
in
  if numbers && tail then VersionRead(major, minor, patch, after <> 45)
  else VersionUnreadable()
end

(* Whether a version is at least the floor; a pre-release of the floor
   itself is below it, as semver orders it *)
fn _at_least (major: int, minor: int, patch: int, release: bool): bool =
  if major <> PLAYWRIGHT_MIN_MAJOR then major > PLAYWRIGHT_MIN_MAJOR
  else if minor <> PLAYWRIGHT_MIN_MINOR then minor > PLAYWRIGHT_MIN_MINOR
  else if patch <> PLAYWRIGHT_MIN_PATCH then patch > PLAYWRIGHT_MIN_PATCH
  else release

fn version_support (v: version_read): support =
  case+ v of
  | ~VersionUnreadable() => PlaywrightUnreadable()
  | ~VersionRead(major, minor, patch, release) =>
    if _at_least(major, minor, patch, release) then PlaywrightSupported()
    else PlaywrightTooOld()

(* The project's Playwright's version (playwright-core's package.json,
   found as the browsers check finds it): its text, status 5 when there is
   none. Nothing of Playwright's is run. *)
#define VERSION_CHECK "node -e 'const p=require(\"path\");try{console.log(require(p.join(p.dirname(require.resolve(\"playwright-core/package.json\",{paths:[process.cwd()]})),\"package.json\")).version)}catch(e){process.exit(5)}'"

(* What the version check found: the version supported, too old or not
   a version, or no answer (no playwright-core, no node: the browsers
   check says so) *)
datatype version_gate =
  | GateOpen
  | GateTooOld
  | GateUnreadable
  | GateNoAnswer

(* The gate, and the version's text (to say it) *)
fn _version_gate (): @(version_gate, $B.builder_v) = let
  var said : $B.builder_v = $B.create()
  val rc = _sh(VERSION_CHECK, $L.list_vt_nil(), said)
  val @(a, k) = $B.to_arr(said)
  val @(fz, bv) = $A.freeze<byte>(a)
  var text : $B.builder_v = $B.create()
  val () = _put_range(bv, 0, k, 524288, text)
  val found = (if rc <> 0 then GateNoAnswer()
    else (case+ version_support(version_read_of(bv, 524288, k)) of
      | PlaywrightSupported() => GateOpen()
      | PlaywrightTooOld() => GateTooOld()
      | PlaywrightUnreadable() => GateUnreadable())): version_gate
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in @(found, text) end

(* ============================================================
   3. The workers
   ============================================================ *)

fn _workers (slots: int): int = let
  var b : $B.builder_v = $B.create()
  val _ = _sh("getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2", $L.list_vt_nil(), b)
  val cores = _number_of(b)
  val c1 = (if cores < 1 then 1 else cores): int
  val s1 = (if slots < 1 then 1 else slots): int
  val per = c1 / (2 * s1)
in if per < 1 then 1 else per end

(* ============================================================
   4, 5, 6. The runs
   ============================================================ *)

(* What a run's keeper said by its status *)
datatype run_end =
  | RunPassed
  | RunFailed         (* Playwright's tests failed *)
  | ServeFailed       (* dist/pwa could not be served *)
  | PlaywrightAbsent  (* Playwright could not be started *)
  | RunStopped        (* stopped: gen-pwa's end, or a signal *)
  | KeeperAbsent      (* node could not be started *)

(* The keeper: serves argv[1] (dist/pwa) on 127.0.0.1 at a port the
   kernel picks, runs argv[2] with the rest in its own process group with
   PWA_TEST_BASE_URL and PWA_TEST_PORT, and exits with its status; when
   its stdin closes (gen-pwa ended) or it is signalled, it stops that
   group and exits 143. 70: it could not serve (an exception in the
   server stops the run the same way); 71: argv[2] could not be
   started. A path with a NUL is refused (400) before the file system
   sees it. *)
#define KEEPER "const http=require('http'),fs=require('fs'),path=require('path'),{spawn}=require('child_process');const [root,cmd,...args]=process.argv.slice(1);const types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.mjs':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json','.webmanifest':'application/manifest+json','.wasm':'application/wasm','.png':'image/png','.jpg':'image/jpeg','.jpeg':'image/jpeg','.gif':'image/gif','.webp':'image/webp','.svg':'image/svg+xml','.ico':'image/x-icon','.woff2':'font/woff2','.woff':'font/woff','.ttf':'font/ttf','.txt':'text/plain; charset=utf-8','.xml':'application/xml','.epub':'application/epub+zip','.map':'application/json'};const base=path.resolve(root);let child=null,stopping=false,code=143;const server=http.createServer((q,r)=>{try{let p;try{p=decodeURIComponent(new URL(q.url,'http://h').pathname)}catch(e){r.writeHead(400);r.end();return}if(p.includes('\\0')){r.writeHead(400);r.end();return}let f=path.join(base,p);if(f!==base&&!f.startsWith(base+path.sep)){r.writeHead(403);r.end();return}fs.stat(f,(e,s)=>{if(!e&&s.isDirectory())f=path.join(f,'index.html');fs.readFile(f,(e2,d)=>{if(e2){r.writeHead(404,{'content-type':'text/plain; charset=utf-8'});r.end('not found');return}r.writeHead(200,{'content-type':types[path.extname(f).toLowerCase()]||'application/octet-stream','cache-control':'no-store'});r.end(q.method==='HEAD'?undefined:d)})})}catch(e){try{r.writeHead(500);r.end()}catch(e2){}}});const stop=()=>{if(stopping)return;stopping=true;if(!child)process.exit(code);try{process.kill(-child.pid,'SIGTERM')}catch(e){}setTimeout(()=>{try{process.kill(-child.pid,'SIGKILL')}catch(e){}process.exit(code)},5000).unref()};process.on('uncaughtException',e=>{console.error('gen-pwa test: the server failed: '+e.message);code=70;stop()});for(const s of ['SIGINT','SIGTERM','SIGHUP'])process.on(s,stop);process.stdin.on('end',stop);process.stdin.on('error',stop);process.stdin.resume();server.on('error',e=>{console.error('gen-pwa test: cannot serve '+root+': '+e.message);process.exit(70)});fs.stat(path.join(base,'index.html'),e=>{if(e){console.error('gen-pwa test: '+root+'/index.html not found: build the app first');process.exit(70)}server.listen(0,'127.0.0.1',()=>{const port=server.address().port;child=spawn(cmd,args,{stdio:['ignore','inherit','inherit'],detached:true,env:{...process.env,PWA_TEST_BASE_URL:'http://127.0.0.1:'+port,PWA_TEST_PORT:String(port)}});child.on('error',e=>{console.error('gen-pwa test: cannot run '+cmd+': '+e.message);process.exit(71)});child.on('exit',(status)=>{try{process.kill(-child.pid,'SIGKILL')}catch(e){}process.exit(stopping?code:(status===null?1:status))})})})"

fn _end_of (status: int): run_end =
  if status = 0 then RunPassed()
  else if status = 70 then ServeFailed()
  else if status = 71 then PlaywrightAbsent()
  else if status = 143 then RunStopped()
  else if status < 0 then KeeperAbsent()
  else RunFailed()

(* b[i, e) as an argument *)
fn _arg_range {l:agz} (b: !$A.borrow(byte, l, 4096), i: int, e: int): $P.arg_entry = let
  var a : $B.builder_v = $B.create()
  val () = _put_range(b, _nat(i), e, 4096, a)
in _arg(a) end

(* The user's Playwright arguments (after "--") pushed onto acc, in
   reverse: whether one of them chooses tests or workers *)
fun _push_user {l:agz}{i:nat} .<max(4096 - i, 0)>.
  (b: !$A.borrow(byte, l, 4096), i: int i, k: int,
   acc: $L.listv($P.arg_entry), chooses: bool): @($L.listv($P.arg_entry), bool) =
  if i >= k then @(acc, chooses)
  else if i >= 4096 then @(acc, chooses)
  else let
    val e = _arg_end(b, i, k)
    val a = _arg_range(b, i, e)
    val c = _is(b, i, e, "--grep", false) || _is(b, i, e, "-g", true)
      || _is(b, i, e, "--workers", false) || _is(b, i, e, "-j", true)
    val next = g1ofg0(e + 1)
  in
    if next <= i then @($L.list_vt_cons(a, acc), chooses || c)
    else _push_user(b, next, k, $L.list_vt_cons(a, acc), chooses || c)
  end

(* Where the user's Playwright arguments start: after "--", or k *)
fun _after_dashes {l:agz}{i:nat} .<max(4096 - i, 0)>.
  (b: !$A.borrow(byte, l, 4096), i: int i, k: int): int =
  if i >= k then k
  else if i >= 4096 then k
  else let
    val e = _arg_end(b, i, k)
    val next = g1ofg0(e + 1)
  in
    if _is(b, i, e, "--", true) then e + 1
    else if next <= i then k
    else _after_dashes(b, next, k)
  end

(* The value after --timings among gen-pwa's own options (argv[2] on,
   before "--"), appended to out: whether it was given *)
fun _timings_from {l:agz}{i:nat} .<max(4096 - i, 0)>.
  (b: !$A.borrow(byte, l, 4096), i: int i, k: int, out: !$B.builder_v >> $B.builder_v): bool =
  if i >= k then false
  else if i >= 4096 then false
  else let
    val e = _arg_end(b, i, k)
    val next = g1ofg0(e + 1)
  in
    if _is(b, i, e, "--", true) then false
    else if _is(b, i, e, "--timings", true) then let
        val v = _nat(e + 1)
        val ve = _arg_end(b, v, k)
        val () = _put_range(b, v, ve, 4096, out)
      in ve > v end
    else if next <= i then false
    else _timings_from(b, next, k, out)
  end

(* Where argv[2] (after the program and "test") starts *)
fn _options_start {l:agz} (b: !$A.borrow(byte, l, 4096), k: int): int = let
  val e0 = _nat(_arg_end(b, 0, k) + 1)
in _arg_end(b, e0, k) + 1 end

(* A run's kind: the @serial tests on one worker; the others; or one run
   of what the user's arguments choose *)
datatype run_kind = SerialRun | ParallelRun | AsGiven

fn _workers_arg (n: int): $P.arg_entry = let
  var w : $B.builder_v = $B.create()
  val () = _bput(w, "--workers=")
  val () = _put_nat(w, n)
in _arg(w) end

(* PLAYWRIGHT_JSON_OUTPUT_NAME=<timings>/<run>.json when --timings was
   given, else nothing: a run without it leaves the caller's own
   variable, and its own reporters, as they are. timings consumed. *)
fn _json_entries (timed: bool, kind: run_kind, timings: $B.builder_v): $L.listv($P.arg_entry) =
  if ~timed then let
    val () = $B.builder_free(timings)
  in $L.list_vt_nil() end
  else let
    var jn : $B.builder_v = $B.create()
    val () = _bput(jn, "PLAYWRIGHT_JSON_OUTPUT_NAME=")
    val @(ta, tk) = $B.to_arr(timings)
    val @(fz_t, bv_t) = $A.freeze<byte>(ta)
    val () = _put_range(bv_t, 0, tk, 524288, jn)
    val () = $A.drop<byte>(fz_t, bv_t)
    val () = $A.free<byte>($A.thaw<byte>(fz_t))
    val () = (case+ kind of
      | SerialRun() => _bput(jn, "/serial.json")
      | ParallelRun() => _bput(jn, "/parallel.json")
      | AsGiven() => _bput(jn, "/run.json"))
  in $L.list_vt_cons(_arg(jn), $L.list_vt_nil()) end

(* Runs the keeper for one run of Playwright: its end *)
fn _run (kind: run_kind, workers: int): run_end = let
  val buf = $A.alloc<byte>(4096)
  val k = _args(buf)
  val @(fz_b, bv_b) = $A.freeze<byte>(buf)
  val opts = _nat(_options_start(bv_b, k))
  var timings : $B.builder_v = $B.create()
  val timed = _timings_from(bv_b, opts, k, timings)
  val user = _nat(_after_dashes(bv_b, opts, k))
  (* node -e KEEPER dist/pwa <playwright> test <ours...> <the user's...>, reversed *)
  var pw : $B.builder_v = $B.create()
  val _ = _playwright(pw)
  val acc = $L.list_vt_cons(_arg_s("test"), $L.list_vt_cons(_arg(pw),
    $L.list_vt_cons(_arg_s("dist/pwa"), $L.list_vt_cons(_arg_s(KEEPER),
    $L.list_vt_cons(_arg_s("-e"), $L.list_vt_cons(_arg_s("node"), $L.list_vt_nil()))))))
  val acc = (case+ kind of
    | SerialRun() => $L.list_vt_cons(_arg_s("--pass-with-no-tests"), $L.list_vt_cons(_workers_arg(1),
        $L.list_vt_cons(_arg_s("@serial"), $L.list_vt_cons(_arg_s("--grep"), acc))))
    | ParallelRun() => $L.list_vt_cons(_arg_s("--pass-with-no-tests"), $L.list_vt_cons(_workers_arg(workers),
        $L.list_vt_cons(_arg_s("@serial"), $L.list_vt_cons(_arg_s("--grep-invert"), acc))))
    | AsGiven() => $L.list_vt_cons(_workers_arg(workers), acc)): $L.listv($P.arg_entry)
  val acc = (if timed then $L.list_vt_cons(_arg_s("--reporter=list,json"), acc) else acc): $L.listv($P.arg_entry)
  val @(acc, _) = _push_user(bv_b, user, k, acc, false)
  val () = $A.drop<byte>(fz_b, bv_b)
  val () = $A.free<byte>($A.thaw<byte>(fz_b))
  (* the environment: the browsers' location, and the timings' file *)
  var bp : $B.builder_v = $B.create()
  val () = _bput(bp, "PLAYWRIGHT_BROWSERS_PATH=")
  val () = _browsers_dir(bp)
  val env = $L.list_vt_cons(_arg(bp), _json_entries(timed, kind, timings))
  val x = _program("node")
  val @(fz_x, bv_x) = $A.freeze<byte>(x)
  val status = (case+ $P.spawn_inherit_env_with(bv_x, _rev(acc, $L.list_vt_nil()), env,
      $P.pipe_new(), $P.inherit(), $P.inherit()) of
    | ~$R.ok(sp) => let
        val+ ~$P.spawn_pipes_mk(child, sin_p, sout_p, serr_p) = sp
        val () = $P.pipe_end_close(sout_p)
        val () = $P.pipe_end_close(serr_p)
        (* sin_p, the keeper's stdin, stays open until it ends: its end,
           at gen-pwa's end however it comes, is what stops the keeper *)
        val ec = (case+ $P.child_wait(child) of | ~$R.ok(n) => n | ~$R.err(_) => 1): int
        val () = $P.pipe_end_close(sin_p)
      in ec end
    | ~$R.err(_) => ~1): int
  val () = $A.drop<byte>(fz_x, bv_x)
  val () = $A.free<byte>($A.thaw<byte>(fz_x))
in _end_of(status) end

(* Says how a run ended: whether it passed *)
fn _said {sn:nat} (name: string sn, e: run_end): bool = let
  var m : $B.builder_v = $B.create()
  val () = _bput(m, "gen-pwa test: ")
  val () = _bput(m, name)
  val passed = (case+ e of RunPassed() => true | _ => false): bool
  val () = (case+ e of
    | RunPassed() => _bput(m, ": passed\n")
    | RunFailed() => _bput(m, ": tests failed\n")
    | ServeFailed() => _bput(m, ": dist/pwa could not be served (see above)\n")
    | PlaywrightAbsent() => _bput(m, ": Playwright could not be started (npm install, or set PWA_TEST_PLAYWRIGHT)\n")
    | RunStopped() => _bput(m, ": stopped\n")
    | KeeperAbsent() => _bput(m, ": node could not be started\n"))
  val () = _say(m)
in passed end

(* ============================================================
   gen-pwa test
   ============================================================ *)

#pub fn gen_test_wanted (): bool

#pub fn gen_test_run (): int

implement gen_test_wanted () = let
  val buf = $A.alloc<byte>(4096)
  val k = _args(buf)
  val @(fz_b, bv_b) = $A.freeze<byte>(buf)
  val s = g1ofg0(_arg_end(bv_b, 0, k) + 1)
  val wanted = (if s < 0 then false
    else if s >= k then false
    else _is(bv_b, s, _arg_end(bv_b, s, k), "test", true)): bool
  val () = $A.drop<byte>(fz_b, bv_b)
  val () = $A.free<byte>($A.thaw<byte>(fz_b))
in wanted end

fun _drop_args {n:nat} .<n>. (xs: $L.list_vt($P.arg_entry, n)): void =
  case+ xs of
  | ~$L.list_vt_nil() => ()
  | ~$L.list_vt_cons(x, tl) => let
      val @(a, _) = x
      val () = $A.free<byte>(a)
    in _drop_args(tl) end

fn _say_s {sn:nat} (s: string sn): void = let
  var m : $B.builder_v = $B.create()
  val () = _bput(m, s)
in _say(m) end

(* before, then what b holds, then after, to stderr; b consumed *)
fn _say_line {sa,sb:nat} (before: string sa, b: $B.builder_v, after: string sb): void = let
  var m : $B.builder_v = $B.create()
  val () = _bput(m, before)
  val @(a, k) = $B.to_arr(b)
  val @(fz, bv) = $A.freeze<byte>(a)
  val () = _put_range(bv, 0, k, 524288, m)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
  val () = _bput(m, after)
in _say(m) end

(* Whether the user's arguments choose the tests or the workers *)
fn _user_chooses (): bool = let
  val buf = $A.alloc<byte>(4096)
  val k = _args(buf)
  val @(fz_b, bv_b) = $A.freeze<byte>(buf)
  val opts = _nat(_options_start(bv_b, k))
  val user = _nat(_after_dashes(bv_b, opts, k))
  val @(acc, chooses) = _push_user(bv_b, user, k, $L.list_vt_nil(), false)
  val () = _drop_args(acc)
  val () = $A.drop<byte>(fz_b, bv_b)
  val () = $A.free<byte>($A.thaw<byte>(fz_b))
in chooses end

(* Where gen-pwa's own options (argv[2] on, before "--") hold one that
   is not --timings <dir>: its start, or ~1 when they are all known *)
fun _unknown_option {l:agz}{i:nat} .<max(4096 - i, 0)>.
  (b: !$A.borrow(byte, l, 4096), i: int i, k: int): int =
  if i >= k then ~1
  else if i >= 4096 then ~1
  else let
    val e = _arg_end(b, i, k)
    val next = _nat(e + 1)
  in
    if _is(b, i, e, "--", true) then ~1
    else if _is(b, i, e, "--timings", true) then let
        val after = _nat(_arg_end(b, next, k) + 1)
      in if after <= i then ~1 else _unknown_option(b, after, k) end
    else i
  end

(* Says an option gen-pwa test does not know: whether there was one *)
fn _options_refused (): bool = let
  val buf = $A.alloc<byte>(4096)
  val k = _args(buf)
  val @(fz_b, bv_b) = $A.freeze<byte>(buf)
  val bad = _unknown_option(bv_b, _nat(_options_start(bv_b, k)), k)
  val () = (if bad >= 0 then let
      var m : $B.builder_v = $B.create()
      val () = _bput(m, "gen-pwa test: unknown option '")
      val () = _put_range(bv_b, _nat(bad), _arg_end(bv_b, _nat(bad), k), 4096, m)
      val () = _bput(m, "': gen-pwa test [--timings <dir>] [-- <playwright args>]\n")
    in _say(m) end else ())
  val () = $A.drop<byte>(fz_b, bv_b)
  val () = $A.free<byte>($A.thaw<byte>(fz_b))
in bad >= 0 end

implement gen_test_run () =
  if _options_refused () then 2 else let
  val held = _lock()
  val () = (case+ held of
    | SlotHeld(_) => ()
    | NoLockDir() => _say_s("gen-pwa test: the lock's directory (PWA_TEST_LOCK_DIR) could not be made: running without the machine's lock\n")
    | NoLockFile() => _say_s("gen-pwa test: a lock file in PWA_TEST_LOCK_DIR could not be opened: running without the machine's lock\n")
    | LockUnsupported() => _say_s("gen-pwa test: the lock's file system has no locks: running without the machine's lock\n"))
  val @(gate, version_text) = _version_gate()
  val gated = (case+ gate of
    | GateOpen() => true
    | GateNoAnswer() => true
    | GateTooOld() => false
    | GateUnreadable() => false): bool
  val () = (case+ gate of
    | GateOpen() => $B.builder_free(version_text)
    | GateNoAnswer() => $B.builder_free(version_text)
    | GateTooOld() => _say_line("gen-pwa test: this project's Playwright is ", version_text,
        ", older than 1.58, whose fake clock ignores a target in the past; before it page.clock.fastForward can set the time back and a test that counts time fails now and then (bats-lang/pwa#92). Install 1.58 or later: npm install --save-dev @playwright/test@^1.58, then npx playwright install chromium\n")
    | GateUnreadable() => _say_line("gen-pwa test: cannot tell the version of this project's Playwright (node_modules/playwright-core/package.json says '", version_text,
        "'), so it cannot be checked against the 1.58 the fake clock needs (bats-lang/pwa#92): npm install, and use a released @playwright/test\n"))
  val @(found, said) = _browsers()
  val ready = (case+ found of
    | BrowsersReady() => gated
    | BrowsersOlder() => false
    | BrowsersMissing() => false
    | NoPlaywrightCore() => false
    | NoNode() => false): bool
  val () = (case+ found of
    | BrowsersReady() => $B.builder_free(said)
    | BrowsersOlder() => _say_line("gen-pwa test: the browsers are older than this Playwright expects: ", said,
        " (install the Playwright they were installed for, or the browsers this one expects: npx playwright install chromium)\n")
    | BrowsersMissing() => _say_line("gen-pwa test: the browser this Playwright expects is not installed: ", said,
        " (npx playwright install chromium; set PLAYWRIGHT_BROWSERS_PATH where they are)\n")
    | NoPlaywrightCore() => let
        val () = $B.builder_free(said)
      in _say_s("gen-pwa test: the project has no Playwright (node_modules/playwright-core): npm install\n") end
    | NoNode() => let
        val () = $B.builder_free(said)
      in _say_s("gen-pwa test: node cannot be run: Playwright needs Node.js\n") end)
  val status = (if ~ready then 1
    else let
      val workers = _workers(_slots())
    in
      if _user_chooses() then (if _said("tests as given", _run(AsGiven(), workers)) then 0 else 1)
      else let
        val serial = _said("@serial tests, alone on one worker", _run(SerialRun(), workers))
        val parallel = _said("the other tests", _run(ParallelRun(), workers))
      in if serial && parallel then 0 else 1 end
    end): int
  val () = _unlock(held)
in status end

(* ============================================================
   Tests (bats test): the Playwright version check, bats-lang/pwa#92
   ============================================================ *)

$UNITTEST.run begin
fun _load {sn:nat}{l:agz}{i:nat | i <= sn} .<sn - i>.
  (a: !$A.arr(byte, l, 4096), s: string sn, n: int sn, i: int i): void =
  if i >= n then ()
  else if i >= 4096 then ()
  else let
    val () = $A.set<byte>(a, i, int2byte0(char2int0(string_get_at(s, i))))
  in _load(a, s, n, i + 1) end

(* The support the check gives the text s *)
fn _support_of {sn:nat} (s: string sn): support = let
  val a = $A.alloc<byte>(4096)
  val n = g1u2i(string1_length(s))
  val () = _load(a, s, n, 0)
  val @(fz, bv) = $A.freeze<byte>(a)
  val k = (if n > 4096 then 4096 else n): int
  val r = version_support(version_read_of(bv, 4096, k))
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in r end

fn _accepted {sn:nat} (s: string sn): bool =
  (case+ _support_of(s) of
   | PlaywrightSupported() => true
   | PlaywrightTooOld() => false
   | PlaywrightUnreadable() => false)

fn _too_old {sn:nat} (s: string sn): bool =
  (case+ _support_of(s) of
   | PlaywrightSupported() => false
   | PlaywrightTooOld() => true
   | PlaywrightUnreadable() => false)

fn _refused_unreadable {sn:nat} (s: string sn): bool =
  (case+ _support_of(s) of
   | PlaywrightSupported() => false
   | PlaywrightTooOld() => false
   | PlaywrightUnreadable() => true)

fn test_just_below_the_floor (): bool = _too_old("1.57.9")
fn test_the_floor (): bool = _accepted("1.58.0")
fn test_the_locked_version (): bool = _accepted("1.58.2")
(* 100 is more than 58, though "1.100.0" sorts before "1.58.0" as text *)
fn test_numbers_not_text (): bool = _accepted("1.100.0") && _too_old("1.9.0")
fn test_next_major (): bool = _accepted("2.0.0") && _accepted("10.0.0")
fn test_older_majors (): bool = _too_old("0.99.99") && _too_old("1.0.0") && _too_old("1.56.1")
(* semver: a pre-release of the floor is before it; of anything later, not *)
fn test_pre_release (): bool =
  _too_old("1.58.0-alpha-1") && _too_old("1.57.0-beta.1") && _accepted("1.59.0-alpha-1756")
  && _accepted("1.58.1-rc.1") && _accepted("1.58.0+build.5")
fn test_garbage (): bool =
  _refused_unreadable("") && _refused_unreadable("garbage") && _refused_unreadable("undefined")
  && _refused_unreadable("1") && _refused_unreadable("1.58") && _refused_unreadable("1.58.")
  && _refused_unreadable("1..0") && _refused_unreadable(".58.0") && _refused_unreadable("1.58.x")
  && _refused_unreadable("1.58.0.1") && _refused_unreadable("v1.58.0")
  && _refused_unreadable(" 1.58.0") && _refused_unreadable("1.58.0 ") && _refused_unreadable("-1.58.0")
  && _refused_unreadable("1.58.0-") && _refused_unreadable("1.58.0-a b") && _refused_unreadable("1.58.0x")
fn test_numbers_too_long (): bool =
  _refused_unreadable("1.1000000.0") && _refused_unreadable("99999999999999.0.0")
  && _accepted("1.999999.0")
end
