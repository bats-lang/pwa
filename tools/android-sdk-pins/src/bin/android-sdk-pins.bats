(* android-sdk-pins -- installs the Android SDK packages the smoke test
   runs on at the revisions pins.txt names, each from a download checked
   against the SHA-1 of Google's repository XML (bats-lang/pwa#137). CI
   tooling for android.yml: nothing here is part of what pwa generates or
   of what the app runs. Area keyword: android-smoke (.claude/rules/android-smoke.md).

   android-sdk-pins install <sdk-root>

   run in the directory that holds pins.txt and the packages' package.xml
   files. A line of pins.txt is five words separated by single spaces:

     <name> <url> <sha1> <unzip-into> <package-dir>

   (<unzip-into> and <package-dir> are relative to <sdk-root>; lines that
   are empty or start with # are skipped), and <name>.xml is the package.xml
   that sdkmanager writes for that package. For each line:

   1. The package is as pinned when <package-dir>/package.xml is the very
      bytes of <name>.xml (cmp): nothing is downloaded. sdkmanager, which
      reads that file, then sees the pinned revision as installed.
   2. Else the zip is downloaded with curl (its own retries on a dropped
      connection), and its SHA-1 (sha1sum) must be the pin's. A mismatch
      is not installed: the zip is removed and the download tried again, up
      to ANDROID_SDK_PINS_ATTEMPTS times (default 3, 1 to 10) with a pause
      that doubles from ANDROID_SDK_PINS_PAUSE_S seconds (default 15, 0 to
      3600); after the last the run fails, naming both sums.
   3. <package-dir> is removed, the zip unpacked into <unzip-into>, and
      <name>.xml copied to <package-dir>/package.xml.

   Exit 0: every package is as pinned. 1: one is not (said on stderr, the
   packages before it stay installed). 2: the arguments or pins.txt are
   not usable. pins.txt may hold at most 65535 bytes, the arguments 4095. *)

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

fn _arg (b: $B.builder_v): $P.arg_entry = let
  val @(a, k) = $B.into_arr(b)
in @(a, k) end

fn _arg_s {sn:nat} (s: string sn): $P.arg_entry = let
  var b : $B.builder_v = $B.create()
  val () = _bput(b, s)
in _arg(b) end

(* the pins file's bytes [s, e) as an argument *)
fn _arg_tok {lp:agz}{s:nat}
  (pb: !$A.borrow(byte, lp, 65536), s: int s, e: int): $P.arg_entry = let
  var b : $B.builder_v = $B.create()
  val () = _put_range(pb, s, e, 65536, b)
in _arg(b) end

(* the pins file's bytes [s, e), then after *)
fn _arg_tok_s {lp:agz}{s:nat}{sn:nat}
  (pb: !$A.borrow(byte, lp, 65536), s: int s, e: int, after: string sn): $P.arg_entry = let
  var b : $B.builder_v = $B.create()
  val () = _put_range(pb, s, e, 65536, b)
  val () = _bput(b, after)
in _arg(b) end

(* the SDK root (the argument's bytes [rs, re)), a slash, then the pins file's bytes [s, e) *)
fn _arg_root_tok {la:agz}{lp:agz}{rs,s:nat}
  (ab: !$A.borrow(byte, la, 4096), rs: int rs, re: int,
   pb: !$A.borrow(byte, lp, 65536), s: int s, e: int): $P.arg_entry = let
  var b : $B.builder_v = $B.create()
  val () = _put_range(ab, rs, re, 4096, b)
  val () = _put(b, 47)
  val () = _put_range(pb, s, e, 65536, b)
in _arg(b) end

(* the SDK root, a slash, the pins file's bytes [s, e), then after *)
fn _arg_root_tok_s {la:agz}{lp:agz}{rs,s:nat}{sn:nat}
  (ab: !$A.borrow(byte, la, 4096), rs: int rs, re: int,
   pb: !$A.borrow(byte, lp, 65536), s: int s, e: int, after: string sn): $P.arg_entry = let
  var b : $B.builder_v = $B.create()
  val () = _put_range(ab, rs, re, 4096, b)
  val () = _put(b, 47)
  val () = _put_range(pb, s, e, 65536, b)
  val () = _bput(b, after)
in _arg(b) end

(* the SDK root followed by s *)
fn _arg_root_s {la:agz}{rs:nat}{sn:nat}
  (ab: !$A.borrow(byte, la, 4096), rs: int rs, re: int, s: string sn): $P.arg_entry = let
  var b : $B.builder_v = $B.create()
  val () = _put_range(ab, rs, re, 4096, b)
  val () = _bput(b, s)
in _arg(b) end

fn _args2 (a: $P.arg_entry, b: $P.arg_entry): $L.listv($P.arg_entry) =
  $L.list_vt_cons(a, $L.list_vt_cons(b, $L.list_vt_nil()))

fn _args3 (a: $P.arg_entry, b: $P.arg_entry, c: $P.arg_entry): $L.listv($P.arg_entry) =
  $L.list_vt_cons(a, _args2(b, c))

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

fn _say_s {sn:nat} (s: string sn): void = let
  var m : $B.builder_v = $B.create()
  val () = _bput(m, s)
in _say(m) end

(* before, the pins file's bytes [s, e), then after, to stderr *)
fn _say_tok {lp:agz}{s:nat}{sa,sb:nat}
  (before: string sa, pb: !$A.borrow(byte, lp, 65536), s: int s, e: int, after: string sb): void = let
  var m : $B.builder_v = $B.create()
  val () = _bput(m, before)
  val () = _put_range(pb, s, e, 65536, m)
  val () = _bput(m, after)
in _say(m) end

(* ============================================================
   Running a command
   ============================================================ *)

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

(* prog (found on PATH) with args: the first line of its stdout appended
   to out, and its status (-1 when it could not be run). Its stderr is
   shown; its stdin is empty. *)
fn _run {sn:nat | sn < $B.BUILDER_CAP}
  (prog: string sn, args: $L.listv($P.arg_entry), out: !$B.builder_v >> $B.builder_v): int = let
  val @(nul_x | x) = $P.path_of_string_proved(prog)
  val @(fz_x, bv_x) = $A.barr_freeze(x)
  val argv = $L.list_vt_cons(_arg_s(prog), args)
  val buf = $A.alloc<byte>(4096)
  val rc = (case+ $P.spawn_inherit_env_proved(nul_x | bv_x, argv, $P.dev_null(), $P.pipe_new(), $P.inherit()) of
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
  val () = $A.cborrow_drop(fz_x, bv_x)
  val () = $A.barr_free($A.barr_thaw(fz_x))
in rc end

(* As _run, the output dropped *)
fn _run_quiet {sn:nat | sn < $B.BUILDER_CAP}
  (prog: string sn, args: $L.listv($P.arg_entry)): int = let
  var ignored : $B.builder_v = $B.create()
  val rc = _run(prog, args, ignored)
  val () = $B.builder_free(ignored)
in rc end

(* ============================================================
   The environment, the arguments, the pins file
   ============================================================ *)

fun _fill {sn:nat}{l:agz}{i:nat | i <= sn} .<sn - i>.
  (a: !$A.arr(byte, l, sn), s: string sn, n: int sn, i: int i): void =
  if i >= n then ()
  else let
    val () = $A.set<byte>(a, i, int2byte0(char2int0(string_get_at(s, i))))
  in _fill(a, s, n, i + 1) end

(* The variable name's value appended to out: whether it is set and not empty *)
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

(* The variable's number, else dflt, kept within lo and hi *)
fn _number_env {sn:pos | sn < 1048576} (name: string sn, dflt: int, lo: int, hi: int): [m:nat] int m = let
  var b : $B.builder_v = $B.create()
  val set = _env(name, b)
  val n = _number_of(b)
  val r = (if ~set then dflt else if n < lo then lo else if n > hi then hi else n): int
  val r1 = g1ofg0(r)
in if r1 >= 0 then r1 else 0 end

(* The process's arguments, NUL-separated, into buf: their length *)
fn _args {l:agz} (buf: !$A.arr(byte, l, 4096)): int =
  case+ $E.args_read(buf, 4096) of
  | ~$R.some(k) => k
  | ~$R.none() => 0

(* Where the argument starting at i ends (its NUL), within k *)
fun _arg_end {l:agz}{i:nat} .<max(4096 - i, 0)>.
  (b: !$A.borrow(byte, l, 4096), i: int i, k: int): [j:nat | j >= i] int j =
  if i >= k then i
  else if i >= 4096 then i
  else if byte2int0($A.read<byte>(b, i)) = 0 then i
  else _arg_end(b, i + 1, k)

(* Whether b[s, e) is exactly lit *)
fn _is {sn:nat}{l:agz}{n:pos}{s:nat}
  (b: !$A.borrow(byte, l, n), s: int s, e: int, lit: string sn, n: int n): bool = let
  val len = g1u2i(string1_length(lit))
  fun loop {sl:nat}{j:nat | j <= sl} .<sl - j>.
    (b: !$A.borrow(byte, l, n), s: int s, e: int, lit: string sl, len: int sl, j: int j, n: int n): bool =
    if j >= len then true
    else if s + j >= n then false
    else if s + j >= e then false
    else if byte2int0($A.read<byte>(b, s + j)) <> char2int0(string_get_at(lit, j)) then false
    else loop(b, s, e, lit, len, j + 1, n)
in e - s = len && loop(b, s, e, lit, len, 0, n) end

(* The pins file and its size: at most 65535 bytes (0: it cannot be read) *)
fn _read_pins {l:agz} (buf: !$A.arr(byte, l, 65536)): int = let
  var p : $B.builder_v = $B.create()
  val () = _bput(p, "pins.txt")
  val () = _put(p, 0)
  val @(pa, _) = $B.to_arr(p)
  val @(fz_p, bv_p) = $A.freeze<byte>(pa)
  val r = (case+ $F.file_open(bv_p, 524288, $F.ReadOnly(), $F.OpenExisting(), 0) of
    | ~$R.err(_) => ~1
    | ~$R.ok(fd) => let
        val size = (case+ $F.fd_size(fd) of | ~$R.ok(s) => s | ~$R.err(_) => ~1): int
        val k = (if size < 0 then ~1
          else if size >= 65536 then ~2
          else (case+ $F.file_read(fd, buf, 65536) of
            | ~$R.ok(n) => (if n = size then n else ~1)
            | ~$R.err(_) => ~1)): int
        val () = $R.discard<int><$F.io_error>($F.file_close(fd))
      in k end): int
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in r end

(* ============================================================
   One package
   ============================================================ *)

(* The end of the token starting at i: the first space or newline, else k *)
fun _tok_end {l:agz}{i:nat} .<max(65536 - i, 0)>.
  (b: !$A.borrow(byte, l, 65536), i: int i, k: int): [j:nat | j >= i] int j =
  if i >= k then i
  else if i >= 65536 then i
  else let
    val c = byte2int0($A.read<byte>(b, i))
  in
    if c = 32 then i else if c = 10 then i else _tok_end(b, i + 1, k)
  end

(* The end of the line starting at i: the first newline, else k *)
fun _line_end {l:agz}{i:nat} .<max(65536 - i, 0)>.
  (b: !$A.borrow(byte, l, 65536), i: int i, k: int): [j:nat | j >= i] int j =
  if i >= k then i
  else if i >= 65536 then i
  else if byte2int0($A.read<byte>(b, i)) = 10 then i
  else _line_end(b, i + 1, k)

(* Whether the first 40 bytes of the line sha1sum printed (out) are the
   pin's, the bytes [hs, he) of the pins file, and a space follows *)
fn _sha1_is {lp:agz}{hs:nat}
  (out: $B.builder_v, pb: !$A.borrow(byte, lp, 65536), hs: int hs, he: int, status: int): bool = let
  val @(a, k) = $B.to_arr(out)
  val @(fz, bv) = $A.freeze<byte>(a)
  fun loop {l:agz}{i:nat | i <= 40} .<40 - i>.
    (bv: !$A.borrow(byte, l, 524288), pb: !$A.borrow(byte, lp, 65536), i: int i, h: int, k: int): bool =
    if i >= 40 then true
    else let
      val at = g1ofg0(h + i)
    in
      if at < 0 then false
      else if at >= 65536 then false
      else if byte2int0($A.read<byte>(bv, i)) <> byte2int0($A.read<byte>(pb, at)) then false
      else loop(bv, pb, i + 1, h, k)
    end
  val same = (if status <> 0 then false
    else if he - hs <> 40 then false
    else if k < 41 then false
    else if k > 524288 then false
    else if byte2int0($A.read<byte>(bv, 40)) <> 32 then false
    else loop(bv, pb, 0, hs, k)): bool
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in same end

(* <root>/.android-sdk-pins/<name>.zip *)
fn _zip_arg {la:agz}{lp:agz}{rs,ns:nat}
  (ab: !$A.borrow(byte, la, 4096), rs: int rs, re: int,
   pb: !$A.borrow(byte, lp, 65536), ns: int ns, ne: int): $P.arg_entry = let
  var b : $B.builder_v = $B.create()
  val () = _put_range(ab, rs, re, 4096, b)
  val () = _bput(b, "/.android-sdk-pins/")
  val () = _put_range(pb, ns, ne, 65536, b)
  val () = _bput(b, ".zip")
in _arg(b) end

(* <root>/<package-dir>/package.xml *)
fn _pkgxml_arg {la:agz}{lp:agz}{rs,ps:nat}
  (ab: !$A.borrow(byte, la, 4096), rs: int rs, re: int,
   pb: !$A.borrow(byte, lp, 65536), ps: int ps, pe: int): $P.arg_entry = let
  var b : $B.builder_v = $B.create()
  val () = _put_range(ab, rs, re, 4096, b)
  val () = _put(b, 47)
  val () = _put_range(pb, ps, pe, 65536, b)
  val () = _bput(b, "/package.xml")
in _arg(b) end

(* sleep pause *)
fn _pause (pause: int): void = let
  var p : $B.builder_v = $B.create()
  val () = _put_nat(p, pause)
  val _ = _run_quiet("sleep", $L.list_vt_cons(_arg(p), $L.list_vt_nil()))
in () end

(* rm -f of the zip *)
fn _drop_zip {la:agz}{lp:agz}{rs,ns:nat}
  (ab: !$A.borrow(byte, la, 4096), rs: int rs, re: int,
   pb: !$A.borrow(byte, lp, 65536), ns: int ns, ne: int): void = let
  val _ = _run_quiet("rm", _args2(_arg_s("-f"), _zip_arg(ab, rs, re, pb, ns, ne)))
in () end

(* Downloads the zip of the line and checks its SHA-1, again (after a pause
   of pause seconds, doubled each time) while tries remain; whether the
   zip is there and is the pinned one. A zip that is not is removed. *)
fun _fetch {la:agz}{lp:agz}{rs,ns,us,hs:nat}{left:nat} .<left>.
  (ab: !$A.borrow(byte, la, 4096), rs: int rs, re: int,
   pb: !$A.borrow(byte, lp, 65536), ns: int ns, ne: int, us: int us, ue: int, hs: int hs, he: int,
   left: int left, pause: int): bool = let
  val rc = _run_quiet("curl", $L.list_vt_cons(_arg_s("--fail"), $L.list_vt_cons(_arg_s("--silent"),
    $L.list_vt_cons(_arg_s("--show-error"), $L.list_vt_cons(_arg_s("--location"),
    $L.list_vt_cons(_arg_s("--retry"), $L.list_vt_cons(_arg_s("3"),
    $L.list_vt_cons(_arg_s("--retry-delay"), $L.list_vt_cons(_arg_s("5"),
    $L.list_vt_cons(_arg_s("--retry-connrefused"), $L.list_vt_cons(_arg_s("--output"),
    $L.list_vt_cons(_zip_arg(ab, rs, re, pb, ns, ne), $L.list_vt_cons(_arg_tok(pb, us, ue), $L.list_vt_nil())))))))))))))
in
  if rc <> 0 then let
    val () = _say_tok("android-sdk-pins: ", pb, ns, ne, ": the download failed (curl exited non-zero), nothing was installed from it\n")
    val () = _drop_zip(ab, rs, re, pb, ns, ne)
  in
    if left <= 1 then false
    else let val () = _pause(pause) in _fetch(ab, rs, re, pb, ns, ne, us, ue, hs, he, left - 1, pause * 2) end
  end
  else let
    var sum : $B.builder_v = $B.create()
    val rc2 = _run("sha1sum", $L.list_vt_cons(_zip_arg(ab, rs, re, pb, ns, ne), $L.list_vt_nil()), sum)
    val ok = _sha1_is(sum, pb, hs, he, rc2)
  in
    if ok then true
    else if rc2 <> 0 then let
      val () = _say_tok("android-sdk-pins: ", pb, ns, ne, ": sha1sum could not check the download\n")
      val () = _drop_zip(ab, rs, re, pb, ns, ne)
    in false end
    else let
      val () = _say_tok("android-sdk-pins: ", pb, ns, ne, ": the download is not the pinned one: its SHA-1 differs from the pin ")
      val () = _say_tok("", pb, hs, he, "; not installed\n")
      val () = _drop_zip(ab, rs, re, pb, ns, ne)
    in
      if left <= 1 then false
      else let val () = _pause(pause) in _fetch(ab, rs, re, pb, ns, ne, us, ue, hs, he, left - 1, pause * 2) end
    end
  end
end

(* Makes the package of the line as pinned: 0 when it is, else 1 *)
fn _install {la:agz}{lp:agz}{rs,ns,us,hs,ds,ps,at:nat}
  (ab: !$A.borrow(byte, la, 4096), rs: int rs, re: int,
   pb: !$A.borrow(byte, lp, 65536), ns: int ns, ne: int, us: int us, ue: int, hs: int hs, he: int,
   ds: int ds, de: int, ps: int ps, pe: int, attempts: int at, pause: int): int = let
  val same = _run_quiet("cmp", $L.list_vt_cons(_arg_s("-s"),
    $L.list_vt_cons(_arg_tok_s(pb, ns, ne, ".xml"), $L.list_vt_cons(_pkgxml_arg(ab, rs, re, pb, ps, pe), $L.list_vt_nil()))))
in
  if same = 0 then let
    val () = _say_tok("android-sdk-pins: ", pb, ns, ne, ": already the pinned revision\n")
  in 0 end
  else let
    val made = _run_quiet("mkdir", _args2(_arg_s("-p"), _arg_root_s(ab, rs, re, "/.android-sdk-pins")))
  in
    if made <> 0 then let
      val () = _say_s("android-sdk-pins: cannot make the download directory under the SDK root\n")
    in 1 end
    else if ~_fetch(ab, rs, re, pb, ns, ne, us, ue, hs, he, attempts, pause) then let
      val () = _say_tok("android-sdk-pins: ", pb, ns, ne, ": no download that matches the pinned SHA-1 could be had: refused\n")
    in 1 end
    else let
      val removed = _run_quiet("rm", _args3(_arg_s("-rf"), _arg_s("--"), _arg_root_tok(ab, rs, re, pb, ps, pe)))
      val into = _run_quiet("mkdir", _args2(_arg_s("-p"), _arg_root_tok(ab, rs, re, pb, ds, de)))
      val unzipped = (if removed <> 0 then ~1 else if into <> 0 then ~1
        else _run_quiet("unzip", $L.list_vt_cons(_arg_s("-q"), $L.list_vt_cons(_arg_s("-o"),
          $L.list_vt_cons(_zip_arg(ab, rs, re, pb, ns, ne), $L.list_vt_cons(_arg_s("-d"),
          $L.list_vt_cons(_arg_root_tok(ab, rs, re, pb, ds, de), $L.list_vt_nil()))))))): int
      val copied = (if unzipped <> 0 then ~1
        else _run_quiet("cp", _args2(_arg_tok_s(pb, ns, ne, ".xml"), _pkgxml_arg(ab, rs, re, pb, ps, pe)))): int
      val _ = _run_quiet("rm", _args2(_arg_s("-f"), _zip_arg(ab, rs, re, pb, ns, ne)))
    in
      if copied = 0 then let
        val () = _say_tok("android-sdk-pins: ", pb, ns, ne, ": installed, SHA-1 of the download as pinned\n")
      in 0 end
      else let
        val _ = _run_quiet("rm", _args3(_arg_s("-rf"), _arg_s("--"), _arg_root_tok(ab, rs, re, pb, ps, pe)))
        val () = _say_tok("android-sdk-pins: ", pb, ns, ne, ": the checked download could not be unpacked into place; the package is removed\n")
      in 1 end
    end
  end
end

(* The lines of the pins file from i: 0 when each is installed as pinned,
   1 at the first that is not, 2 at a line that is not five words *)
fun _lines {la:agz}{lp:agz}{rs,i,at:nat} .<max(65536 - i, 0)>.
  (ab: !$A.borrow(byte, la, 4096), rs: int rs, re: int,
   pb: !$A.borrow(byte, lp, 65536), i: int i, k: int, attempts: int at, pause: int): int =
  if i >= k then 0
  else if i >= 65536 then 0
  else let
    val le = _line_end(pb, i, k)
  in
    if le <= i then _lines(ab, rs, re, pb, le + 1, k, attempts, pause)
    else if byte2int0($A.read<byte>(pb, i)) = 35 then _lines(ab, rs, re, pb, le + 1, k, attempts, pause)
    else let
      val ne = _tok_end(pb, i, k)
      val us = ne + 1
      val ue = _tok_end(pb, us, k)
      val hs = ue + 1
      val he = _tok_end(pb, hs, k)
      val ds = he + 1
      val de = _tok_end(pb, ds, k)
      val ps = de + 1
      val pe = _tok_end(pb, ps, k)
    in
      if ne <= i then 2
      else if ue <= us then 2
      else if he <= hs then 2
      else if de <= ds then 2
      else if pe <= ps then 2
      else if pe <> le then 2
      else if de >= le then 2
      else let
        val rc = _install(ab, rs, re, pb, i, ne, us, ue, hs, he, ds, de, ps, pe, attempts, pause)
      in
        if rc <> 0 then rc
        else _lines(ab, rs, re, pb, le + 1, k, attempts, pause)
      end
    end
  end

(* ============================================================
   The command
   ============================================================ *)

fn _status (code: int): void =
  if code <> 0 then exit_void(code) else ()

implement main0 () = let
  val buf = $A.alloc<byte>(4096)
  val k = _args(buf)
  val @(fz_a, bv_a) = $A.freeze<byte>(buf)
  val s1 = _arg_end(bv_a, 0, k) + 1
  val e1 = _arg_end(bv_a, s1, k)
  val s2 = e1 + 1
  val e2 = _arg_end(bv_a, s2, k)
  val usable = (k < 4095 && _is(bv_a, s1, e1, "install", 4096) && e2 > s2): bool
  val status = (if ~usable then let
      val () = _say_s("usage: android-sdk-pins install <sdk-root>   (in the directory with pins.txt)\n")
    in 2 end
    else let
      val pins = $A.alloc<byte>(65536)
      val size = _read_pins(pins)
      val @(fz_p, bv_p) = $A.freeze<byte>(pins)
      val code = (if size < 0 then let
          val () = (if size = ~2 then _say_s("android-sdk-pins: pins.txt is larger than 65535 bytes\n")
            else _say_s("android-sdk-pins: cannot read pins.txt in the current directory\n"))
        in 2 end
        else _lines(bv_a, s2, e2, bv_p, 0, size,
          _number_env("ANDROID_SDK_PINS_ATTEMPTS", 3, 1, 10),
          _number_env("ANDROID_SDK_PINS_PAUSE_S", 15, 0, 3600))): int
      val () = $A.drop<byte>(fz_p, bv_p)
      val () = $A.free<byte>($A.thaw<byte>(fz_p))
    in code end): int
  val () = $A.drop<byte>(fz_a, bv_a)
  val () = $A.free<byte>($A.thaw<byte>(fz_a))
in _status(status) end
