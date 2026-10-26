(* smoke_tests -- the tests of the smoke test's retry (bats-lang/pwa#214; area keyword
   android-smoke, .claude/rules/android-smoke.md), run by `bats test` in
   tools/android-sdk-pins after `bats build`, as tools/pin-audit's tests are (they run
   its built binary against stand-ins in a directory of each case under build/).

   Three kinds of case.

   The decision: the built android-sdk-pins `decide`, on every input.

   The wiring of android.yml: the block of lines from attempt 1's name line through the
   line before the upload step's name line is compared with tests/wiring.txt as one exact
   text. Each of the two bounding lines occurs exactly once, the first before the second.
   On the two lines that name the emulator action everything up to and including the at
   sign is compared byte for byte, and the two texts after the at sign (the pin and its
   comment) must be equal on the two lines; the form of a pin is the claim of bats
   check-pins and is not restated here. The claim is exactly this: each line of the block
   is read, so deleting it, changing it, inserting a line after it and swapping it with a
   differing neighbour are each refused; the block is not cut when a bounding line is
   absent, repeated or out of order; the two texts after the at sign must be equal. The
   cases are generated from the lines of the real android.yml and played on every run:
   for each line of the block one edit of each kind (deleted, last compared byte changed,
   a line of continue-on-error added after it, swapped with the next line), five cut cases,
   two mask cases, and three controls that are accepted. A case that is accepted fails the
   run and names its class and the index of its line; no case prints a line of the block.

   The flow: the steps played in android.yml's order with a stand-in sdkmanager (a
   cut-short manifest on its first call, then the whole one) and a stand-in action (the
   install, the marker, the test). The flow fails, and is not skipped, when the wiring
   check refuses the real android.yml. The stand-ins and the tool are built binaries,
   copied to the case's directory and run there with `env -C`. *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use file as F
#use list as L
#use process as P
#use result as R

staload "smoke_files.sats"

(* build/smoke-tests/<name> as a builder, then /<file> when file is not empty *)
fn _case_path {n,m:nat | n < 100; m < 200} (name: string n, file: string m): $B.builder_v = let
  var out : $B.builder(0) = $B.create()
  val () = $B.bput(out, "build/smoke-tests/")
  val () = $B.bput(out, name)
  val () = $B.bput(out, "/")
  val () = $B.bput(out, file)
in out end

fn _case_arg {n:nat | n < 100} (name: string n): $P.arg_entry = let
  var out : $B.builder(0) = $B.create()
  val () = $B.bput(out, "build/smoke-tests/")
  val () = $B.bput(out, name)
in arg_of(out) end

(* NAME=value as one argument *)
fn _assign {n,m:nat | n < 100; m < 100} (name: string n, value: string m): $P.arg_entry = let
  var out : $B.builder(0) = $B.create()
  val () = $B.bput(out, name)
  val () = $B.bput(out, "=")
  val () = $B.bput(out, value)
in arg_of(out) end

fn _no_arguments (): $L.listv($P.arg_entry) = $L.list_vt_nil()

fn _one (first: $P.arg_entry): $L.listv($P.arg_entry) = $L.list_vt_cons(first, $L.list_vt_nil())

fn _two (first: $P.arg_entry, second: $P.arg_entry): $L.listv($P.arg_entry) =
  $L.list_vt_cons(first, _one(second))

fn _three (first: $P.arg_entry, second: $P.arg_entry, third: $P.arg_entry): $L.listv($P.arg_entry) =
  $L.list_vt_cons(first, _two(second, third))

(* A fresh directory for the case, with the tool and the two stand-ins in its bin, the
   file cut as long as cut says (the manifests that come cut short), and the file
   test-fails when the test fails *)
fn _fresh {n:nat | n < 100}{c:nat | c <= 5} (name: string n, cut: int c, test_fails: bool): void = let
  val _ = run_program("rm", _three(arg_text("-rf"), arg_text("--"), _case_arg(name)), _no_arguments())
  val _ = run_program("mkdir", _three(arg_text("-p"), arg_text("--"), arg_of(_case_path(name, "bin"))), _no_arguments())
  val _ = run_program("cp", _two(arg_text("dist/debug/android-sdk-pins"), arg_of(_case_path(name, "bin/android-sdk-pins"))), _no_arguments())
  val _ = run_program("cp", _two(arg_text("dist/debug/action_stand_in"), arg_of(_case_path(name, "bin/action"))), _no_arguments())
  val _ = run_program("cp", _two(arg_text("dist/debug/sdkmanager_stand_in"), arg_of(_case_path(name, "bin/sdkmanager"))), _no_arguments())
  fun cuts {n:nat | n < 100}{k:nat} .<k>. (name: string n, k: int k): void =
    if k <= 0 then ()
    else let val _ = append_x(_case_path(name, "cut")) in cuts(name, k - 1) end
  val () = cuts(name, cut)
  val () = (if test_fails then let val _ = append_x(_case_path(name, "test-fails")) in () end else ())
in () end

(* program in the case's directory (env -C), PATH starting at its bin, with extra *)
fn _in_case {n,p:nat | n < 100; p < 100} (name: string n, program: string p, args: $L.listv($P.arg_entry),
  extra: $L.listv($P.arg_entry)): int = let
  val argv = $L.list_vt_cons(arg_text("-C"), $L.list_vt_cons(_case_arg(name), $L.list_vt_cons(arg_text(program), args)))
in run_program("env", argv, $L.list_vt_cons(arg_text("PATH=bin:/usr/bin:/bin"), extra)) end

(* the decision of the tool, in the case's directory: its status and whether it printed the line *)
fn _decide {n:nat | n < 100}{o,l:nat | o < 100; l < 100}
  (name: string n, outcome: string o, attempt: string 1, attempts: string 1, line: string l, marker_argument: bool): @(int, bool) = let
  val marker = (if marker_argument then _one(arg_text("emulator-installed")) else _no_arguments()): $L.listv($P.arg_entry)
  val argv = $L.list_vt_cons(arg_text("-C"), $L.list_vt_cons(_case_arg(name),
    $L.list_vt_cons(arg_text("bin/android-sdk-pins"), $L.list_vt_cons(arg_text("decide"), marker))))
  val extra = $L.list_vt_cons(_assign("ANDROID_SMOKE_OUTCOME", outcome), _three(_assign("ANDROID_SMOKE_ATTEMPT", attempt),
    _assign("ANDROID_SMOKE_ATTEMPTS", attempts), arg_text("PATH=bin:/usr/bin:/bin")))
in run_says("env", argv, extra, line) end

(* ============================================================
   The wiring of android.yml: one comparison of a block with tests/wiring.txt
   ============================================================ *)

(* the byte at i, ~1 outside the buffer *)
fn _at {l:agz}{i:int} (view: !$A.borrow(byte, l, 131072), i: int i): int =
  if i >= 0 then (if i < 131072 then byte2int0($A.read<byte>(view, i)) else ~1) else ~1

(* the place after the line that starts at i (after its newline, else the end) *)
fun _eol {l:agz}{count:nat | count <= 131072}{i:nat | i <= count} .<count - i>.
  (view: !$A.borrow(byte, l, 131072), count: int count, i: int i): [r:int | i <= r; r <= count] int r =
  if i >= count then i
  else if byte2int0($A.read<byte>(view, i)) = 10 then i + 1
  else _eol(view, count, i + 1)

(* whether the len bytes of a at ai are those of b at bi *)
fun _same_loop {al,bl:agz}{ai,bi:nat}{len:nat | ai + len <= 131072; bi + len <= 131072}{j:nat | j <= len} .<len - j>.
  (av: !$A.borrow(byte, al, 131072), bv: !$A.borrow(byte, bl, 131072), ai: int ai, bi: int bi, len: int len, j: int j): bool =
  if j >= len then true
  else if byte2int0($A.read<byte>(av, ai + j)) <> byte2int0($A.read<byte>(bv, bi + j)) then false
  else _same_loop(av, bv, ai, bi, len, j + 1)

fn _same {al,bl:agz}{ac,bc:nat | ac <= 131072; bc <= 131072}{ai,bi,len:int}
  (av: !$A.borrow(byte, al, 131072), ac: int ac, ai: int ai, bv: !$A.borrow(byte, bl, 131072), bc: int bc, bi: int bi, len: int len): bool =
  if ai < 0 then false
  else if bi < 0 then false
  else if len < 0 then false
  else if ai + len > ac then false
  else if bi + len > bc then false
  else _same_loop(av, bv, ai, bi, len, 0)

(* whether the len bytes at ai are those at bi, in one buffer (false when a range leaves the buffer) *)
fun _same_in_loop {l:agz}{ai,bi:nat}{len:nat | ai + len <= 131072; bi + len <= 131072}{j:nat | j <= len} .<len - j>.
  (v: !$A.borrow(byte, l, 131072), ai: int ai, bi: int bi, len: int len, j: int j): bool =
  if j >= len then true
  else if byte2int0($A.read<byte>(v, ai + j)) <> byte2int0($A.read<byte>(v, bi + j)) then false
  else _same_in_loop(v, ai, bi, len, j + 1)

fn _same_in {l:agz}{c:nat | c <= 131072}{ai,bi,len:int}
  (v: !$A.borrow(byte, l, 131072), c: int c, ai: int ai, bi: int bi, len: int len): bool =
  if ai < 0 then false
  else if bi < 0 then false
  else if len < 0 then false
  else if ai + len > c then false
  else if bi + len > c then false
  else _same_in_loop(v, ai, bi, len, 0)

(* the place of the literal when it occurs exactly once, else ~1 *)
fn _once {l:agz}{count:nat | count <= 131072}{literal_size:nat}
  (view: !$A.borrow(byte, l, 131072), count: int count, literal: string literal_size): [p:int | ~1 <= p; p <= count] int p = let
  val first = find_from(view, count, 0, literal)
in
  if first < 0 then ~1
  else if first + 1 > count then first
  else if find_from(view, count, first + 1, literal) < 0 then first
  else ~1
end

(* the block's start and its end (the start of the upload step's name line), ~1 and ~1
   when a bounding line is absent, repeated or out of order *)
fn _cut {l:agz}{count:nat | count <= 131072}
  (view: !$A.borrow(byte, l, 131072), count: int count): [s,e:int | ~1 <= s; s <= e; e <= count] @(int s, int e) = let
  val s = _once(view, count, "      - name: Run the app on an emulator (attempt 1 of 2)\n")
  val e = _once(view, count, "      - name: Upload screenshot, UI dump and logcat\n")
in
  if s < 0 then @(~1, ~1) else if e < 0 then @(~1, ~1) else if s >= e then @(~1, ~1) else @(s, e)
end

(* the lines of the block against the lines of the golden text, in lockstep: a golden line
   that ends in @PIN stands for a line that has the same bytes up to and including the at sign
   and any text after it, the two such texts equal; the other lines are equal byte for byte *)
fun _walk {yl,gl:agz}{yc,gc:nat | yc <= 131072; gc <= 131072}{ye:nat | ye <= yc}{yp:nat | yp <= yc}{gp:nat | gp <= gc}{fuel:nat | fuel <= 131072}{masks:int}{ms,ml:int} .<fuel>.
  (yv: !$A.borrow(byte, yl, 131072), yc: int yc, ye: int ye, gv: !$A.borrow(byte, gl, 131072), gc: int gc,
   yp: int yp, gp: int gp, fuel: int fuel, masks: int masks, m_start: int ms, m_len: int ml): bool =
  if yp >= ye then (if gp >= gc then masks = 2 else false)
  else if gp >= gc then false
  else if fuel <= 0 then false
  else let
    val y_end = _eol(yv, yc, yp)
    val g_end = _eol(gv, gc, gp)
  in
    if y_end > ye then false
    else if g_end - gp >= 5 && matches_at(gv, gc, g_end - 5, "@PIN\n") then let
      val lead = g_end - 4 - gp
      val m = yp + lead
    in
      if y_end - yp < lead + 1 then false
      else if ~_same(yv, yc, yp, gv, gc, gp, lead) then false
      else if masks = 0 then _walk(yv, yc, ye, gv, gc, y_end, g_end, fuel - 1, 1, m, y_end - 1 - m)
      else if masks = 1 then
        (if y_end - 1 - m = m_len && m_len >= 0 && _same_in(yv, yc, m_start, m, m_len)
         then _walk(yv, yc, ye, gv, gc, y_end, g_end, fuel - 1, 2, m_start, m_len) else false)
      else false
    end
    else if y_end - yp = g_end - gp && _same(yv, yc, yp, gv, gc, gp, y_end - yp)
    then _walk(yv, yc, ye, gv, gc, y_end, g_end, fuel - 1, masks, m_start, m_len)
    else false
  end

(* whether android.yml (the bytes yv) holds the block that the golden text (gv) is *)
fn _wired {yl,gl:agz}{yc,gc:nat | yc <= 131072; gc <= 131072}
  (yv: !$A.borrow(byte, yl, 131072), yc: int yc, gv: !$A.borrow(byte, gl, 131072), gc: int gc): bool = let
  val @(s, e) = _cut(yv, yc)
in
  if s < 0 then false else _walk(yv, yc, e, gv, gc, s, 0, 131072, 0, 0, 0)
end

(* The two files, read: the real android.yml and tests/wiring.txt; their sizes (~1 when one cannot be read) *)
fn _load {yl,gl:agz} (yml: !$A.arr(byte, yl, 131072), gold: !$A.arr(byte, gl, 131072))
  : @([y:int | ~1 <= y; y <= 131072] int y, [g:int | ~1 <= g; g <= 131072] int g) = let
  val y = read_into(text_of("../../.github/workflows/android.yml"), yml)
  val g = read_into(text_of("tests/wiring.txt"), gold)
in @(y, g) end

(* whether the real android.yml holds the block of tests/wiring.txt *)
fn _real_wired (): bool = let
  val yml = $A.alloc<byte>(131072)
  val gold = $A.alloc<byte>(131072)
  val @(yc, gc) = _load(yml, gold)
  val @(yf, yv) = $A.freeze<byte>(yml)
  val @(gf, gv) = $A.freeze<byte>(gold)
  val ok = (if yc < 0 then false else if gc < 0 then false else _wired(yv, yc, gv, gc)): bool
  val () = $A.drop<byte>(yf, yv)
  val () = $A.free<byte>($A.thaw<byte>(yf))
  val () = $A.drop<byte>(gf, gv)
  val () = $A.free<byte>($A.thaw<byte>(gf))
in ok end

(* ============================================================
   The generated cases
   ============================================================ *)

(* src[from, to) appended to out at pos: the new pos (nothing is written past the buffer) *)
fun _copy_loop {l,k:agz}{start:nat}{stop:int | start <= stop; stop <= 131072}{pos:nat | pos <= 131072} .<stop - start>.
  (src: !$A.borrow(byte, l, 131072), out: !$A.arr(byte, k, 131072), start: int start, stop: int stop, pos: int pos)
  : [r:nat | r <= 131072] int r =
  if start >= stop then pos
  else if pos >= 131072 then pos
  else let
    val () = $A.set<byte>(out, pos, $A.read<byte>(src, start))
  in _copy_loop(src, out, start + 1, stop, pos + 1) end

(* src[start, stop) appended to out at pos: the new pos (nothing is written past the buffer; a range that
   leaves the buffer writes nothing) *)
fn _copy {l,k:agz}{start,stop:int}{pos:nat | pos <= 131072}
  (src: !$A.borrow(byte, l, 131072), out: !$A.arr(byte, k, 131072), start: int start, stop: int stop, pos: int pos)
  : [r:nat | r <= 131072] int r =
  if start < 0 then pos
  else if stop > 131072 then pos
  else if start > stop then pos
  else _copy_loop(src, out, start, stop, pos)

fn _put_byte {k:agz}{pos:nat | pos <= 131072} (out: !$A.arr(byte, k, 131072), pos: int pos, value: int): [r:nat | r <= 131072] int r =
  if pos >= 131072 then pos
  else let
    val () = $A.set<byte>(out, pos, int2byte0(value))
  in pos + 1 end

fun _put_spaces {k:agz}{pos:nat | pos <= 131072}{n:nat} .<n>.
  (out: !$A.arr(byte, k, 131072), pos: int pos, n: int n): [r:nat | r <= 131072] int r =
  if n <= 0 then pos else _put_spaces(out, _put_byte(out, pos, 32), n - 1)

fn _put_text {k:agz}{pos:nat | pos <= 131072}{n:nat} (out: !$A.arr(byte, k, 131072), pos: int pos, text: string n): [r:nat | r <= 131072] int r = let
  fun loop {k:agz}{n:nat}{i:nat | i <= n}{pos:nat | pos <= 131072} .<n - i>.
    (out: !$A.arr(byte, k, 131072), text: string n, size: int n, i: int i, pos: int pos): [r:nat | r <= 131072] int r =
    if i >= size then pos
    else loop(out, text, size, i + 1, _put_byte(out, pos, char2int0(string_get_at(text, i))))
in loop(out, text, g1u2i(string1_length(text)), 0, pos) end

(* the place after the leading spaces of the line that starts at a *)
fun _indent_end {l:agz}{count:nat | count <= 131072}{a:nat | a <= count} .<count - a>.
  (view: !$A.borrow(byte, l, 131072), count: int count, a: int a): [r:int | a <= r; r <= count] int r =
  if a >= count then a
  else if byte2int0($A.read<byte>(view, a)) = 32 then _indent_end(view, count, a + 1)
  else a

(* a byte other than the one at p, as a byte value that is not a newline *)
fn _other {l:agz}{p:int} (view: !$A.borrow(byte, l, 131072), p: int p): int =
  if _at(view, p) = 120 then 121 else 120

(* the place of the first at sign in [a, b), ~1 if none *)
fun _at_sign {l:agz}{count:nat | count <= 131072}{a:nat | a <= count}{b:int | a <= b; b <= count} .<b - a>.
  (view: !$A.borrow(byte, l, 131072), count: int count, a: int a, b: int b): [r:int | ~1 <= r; r <= count] int r =
  if a >= b then ~1
  else if byte2int0($A.read<byte>(view, a)) = 64 then a
  else _at_sign(view, count, a + 1, b)

(* the kinds of edit: D deleted, C last compared byte changed, I a line added after, S swapped with the next *)
(* the file with the edit of the line [a, b) of kind (c is the end of the next line), written to out: its size *)
fn _edit {l,k:agz}{count:nat | count <= 131072}{a:nat | a <= count}{b:int | a <= b; b <= count}{c:int}
  (view: !$A.borrow(byte, l, 131072), count: int count, out: !$A.arr(byte, k, 131072), kind: int, a: int a, b: int b, c: int c)
  : [r:nat | r <= 131072] int r =
  if kind = 0 then _copy(view, out, b, count, _copy(view, out, 0, a, 0))
  else if kind = 1 then let
    val sign = (if b - a > 22 then _at_sign(view, count, a, b) else ~1): [r:int | ~1 <= r; r <= count] int r
    val uses = (sign >= 0 && matches_at(view, count, _indent_end(view, count, a), "uses: reactivecircus/android-emulator-runner@")): bool
  in
    if uses then let
      val p = sign - 1
    in
      if p >= 0 then _copy(view, out, p + 1, count, _put_byte(out, _copy(view, out, 0, p, 0), _other(view, p)))
      else 0
    end
    else if b - a <= 1 then _copy(view, out, a, count, _put_byte(out, _copy(view, out, 0, a, 0), 120))
    else let
      val p = b - 2
    in _copy(view, out, p + 1, count, _put_byte(out, _copy(view, out, 0, p, 0), _other(view, p))) end
  end
  else if kind = 2 then let
    val head = _copy(view, out, 0, b, 0)
    val spaced = _put_spaces(out, head, _indent_end(view, count, a) - a)
  in _copy(view, out, b, count, _put_text(out, spaced, "continue-on-error: true\n")) end
  else _copy(view, out, c, count, _copy(view, out, a, b, _copy(view, out, b, c, _copy(view, out, 0, a, 0))))

(* one class over the block [s, e) of the file: the edit of every line (kind), each of which must be refused;
   the number of mutants played, or a negative number when one is accepted (~1 minus its line index) *)
fun _class_loop {yl,gl:agz}{yc,gc:nat | yc <= 131072; gc <= 131072}{e:int | e <= yc}{a:nat | a <= yc}{fuel:nat | fuel <= 131072} .<fuel>.
  (yv: !$A.borrow(byte, yl, 131072), yc: int yc, gv: !$A.borrow(byte, gl, 131072), gc: int gc, kind: int,
   e: int e, a: int a, index: int, played: int, fuel: int fuel): int =
  if a >= e then played
  else if fuel <= 0 then played
  else let
    val b = _eol(yv, yc, a)
    val c = _eol(yv, yc, b)
    val differ = (if kind = 3 then (if b - a <> c - b then true else ~_same_in(yv, yc, a, b, b - a)) else true): bool
  in
    if b > e then played
    else if ~differ then _class_loop(yv, yc, gv, gc, kind, e, b, index + 1, played, fuel - 1)
    else if kind = 3 && c > e then played
    else let
      val out = $A.alloc<byte>(131072)
      val size = _edit(yv, yc, out, kind, a, b, c)
      val @(oz, ov) = $A.freeze<byte>(out)
      val accepted = _wired(ov, size, gv, gc)
      val () = $A.drop<byte>(oz, ov)
      val () = $A.free<byte>($A.thaw<byte>(oz))
    in
      if accepted then ~1 - index
      else _class_loop(yv, yc, gv, gc, kind, e, b, index + 1, played + 1, fuel - 1)
    end
  end

(* as _eol, for a place that may be outside the buffer (then the end) *)
fn _eol_safe {l:agz}{count:nat | count <= 131072}{i:int} (view: !$A.borrow(byte, l, 131072), count: int count, i: int i): [r:int | r <= count] int r =
  if i < 0 then count else if i > count then count else _eol(view, count, i)

(* the number of lines of [a, e) *)
fun _lines {l:agz}{count:nat | count <= 131072}{a:nat | a <= count}{e:int | e <= count}{fuel:nat | fuel <= 131072} .<fuel>.
  (view: !$A.borrow(byte, l, 131072), count: int count, a: int a, e: int e, fuel: int fuel, n: int): int =
  if a >= e then n
  else if fuel <= 0 then n
  else _lines(view, count, _eol(view, count, a), e, fuel - 1, n + 1)

(* every edit of one kind over the block of the real android.yml is refused; says so *)
fn _class {n:nat} (label: string n, kind: int): bool = let
  val yml = $A.alloc<byte>(131072)
  val gold = $A.alloc<byte>(131072)
  val @(yc, gc) = _load(yml, gold)
  val @(yf, yv) = $A.freeze<byte>(yml)
  val @(gf, gv) = $A.freeze<byte>(gold)
  val ok = (if yc < 0 then false else if gc < 0 then false else let
      val @(s, e) = _cut(yv, yc)
    in
      if s < 0 then false
      else let
        val played = _class_loop(yv, yc, gv, gc, kind, e, s, 0, 0, 131072)
        val lines = _lines(yv, yc, s, e, 131072, 0)
        val () = (if played >= 0 then println! ("class ", label, ": ", played, " mutants over ", lines, " lines of the block, each refused")
          else println! ("class ", label, ": the edit of the line with index ", ~1 - played, " was accepted"))
      in played > 0 end
    end): bool
  val () = $A.drop<byte>(yf, yv)
  val () = $A.free<byte>($A.thaw<byte>(yf))
  val () = $A.drop<byte>(gf, gv)
  val () = $A.free<byte>($A.thaw<byte>(gf))
in ok end

(* whether the file written to out (size bytes) is refused *)
fn _refused {k,gl:agz}{gc:nat | gc <= 131072}{sz:int} (out: $A.arr(byte, k, 131072), size: int sz, gv: !$A.borrow(byte, gl, 131072), gc: int gc): bool = let
  val @(oz, ov) = $A.freeze<byte>(out)
  val clipped = (if size < 0 then 0 else if size > 131072 then 131072 else size): [z:nat | z <= 131072] int z
  val accepted = _wired(ov, clipped, gv, gc)
  val () = $A.drop<byte>(oz, ov)
  val () = $A.free<byte>($A.thaw<byte>(oz))
in ~accepted end

(* the five cut cases, the two mask cases and the three controls, on the real android.yml *)
fn _cut_mask_controls (): bool = let
  val yml = $A.alloc<byte>(131072)
  val gold = $A.alloc<byte>(131072)
  val @(yc, gc) = _load(yml, gold)
  val @(yf, yv) = $A.freeze<byte>(yml)
  val @(gf, gv) = $A.freeze<byte>(gold)
  val ok = (if yc < 0 then false else if gc < 0 then false else let
      val @(s, e) = _cut(yv, yc)
    in
      if s < 0 then false
      else let
        val s2 = _eol(yv, yc, s)
        val e2 = _eol(yv, yc, e)
        val cut_1 = _refused($A.alloc<byte>(131072), 0, gv, gc)
        val o1 = $A.alloc<byte>(131072)
        val n1 = _copy(yv, o1, s2, yc, _copy(yv, o1, 0, s, 0))
        val r1 = _refused(o1, n1, gv, gc)
        val o2 = $A.alloc<byte>(131072)
        val n2 = _copy(yv, o2, e2, yc, _copy(yv, o2, 0, e, 0))
        val r2 = _refused(o2, n2, gv, gc)
        val o3 = $A.alloc<byte>(131072)
        val n3 = _copy(yv, o3, s2, yc, _copy(yv, o3, s, s2, _copy(yv, o3, 0, s2, 0)))
        val r3 = _refused(o3, n3, gv, gc)
        val o4 = $A.alloc<byte>(131072)
        val n4 = _copy(yv, o4, e2, yc, _copy(yv, o4, e, e2, _copy(yv, o4, 0, e2, 0)))
        val r4 = _refused(o4, n4, gv, gc)
        val o5 = $A.alloc<byte>(131072)
        val n5 = _copy(yv, o5, e2, yc, _copy(yv, o5, s, s2, _copy(yv, o5, s2, e, _copy(yv, o5, e, e2, _copy(yv, o5, 0, s, 0)))))
        val r5 = _refused(o5, n5, gv, gc)
        val () = let val verdict = (if r1 && r2 && r3 && r4 && r5 then "each refused" else "one was accepted"): string in println! ("cut cases: first bounding line absent, second absent, first twice, second twice, the two in the other order: ", verdict) end
        (* the masked texts: the first byte after the at sign of each line that names the action *)
        val literal = "android-emulator-runner@"
        val f1 = find_from(yv, yc, s, literal)
        val q1 = (if f1 < 0 then ~1 else f1 + 24): [q:int | ~1 <= q; q <= 131072 + 24] int q
        val f2 = (if f1 < 0 then ~1 else if f1 + 1 > yc then ~1 else find_from(yv, yc, f1 + 1, literal)): [f:int | ~1 <= f; f <= 131072] int f
        val q2 = (if f2 < 0 then ~1 else f2 + 24): [q:int | ~1 <= q; q <= 131072 + 24] int q
        val have = (q1 >= 0 && q1 <= yc && q2 >= 0 && q2 <= yc && q1 < q2): bool
      in
        if ~have then false
        else let
          val m1 = $A.alloc<byte>(131072)
          val k1 = _copy(yv, m1, q1 + 1, yc, _put_byte(m1, _copy(yv, m1, 0, q1, 0), _other(yv, q1)))
          val mr1 = _refused(m1, k1, gv, gc)
          val m2 = $A.alloc<byte>(131072)
          val k2 = _copy(yv, m2, q2 + 1, yc, _put_byte(m2, _copy(yv, m2, 0, q2, 0), _other(yv, q2)))
          val mr2 = _refused(m2, k2, gv, gc)
          val () = let val verdict = (if mr1 && mr2 then "each refused" else "one was accepted"): string in println! ("mask cases: the text after the at sign changed on the first line alone, on the second line alone: ", verdict) end
          val l1 = _eol_safe(yv, yc, q1) - 1
          val l2 = _eol_safe(yv, yc, q2) - 1
          val same_file = _wired(yv, yc, gv, gc)
          (* controls: the two texts replaced by one text, in the two spellings *)
          val c1 = $A.alloc<byte>(131072)
          val t1 = "0123456789012345678901234567890123456789 # v9.9.9"
          val z1 = _copy(yv, c1, l2, yc, _put_text(c1, _copy(yv, c1, l1, q2, _put_text(c1, _copy(yv, c1, 0, q1, 0), t1)), t1))
          val c1_accepted = ~_refused(c1, z1, gv, gc)
          val c2 = $A.alloc<byte>(131072)
          val t2 = "abcdefabcdefabcdefabcdefabcdefabcdefabcd # repository main 0123abc"
          val z2 = _copy(yv, c2, l2, yc, _put_text(c2, _copy(yv, c2, l1, q2, _put_text(c2, _copy(yv, c2, 0, q1, 0), t2)), t2))
          val c2_accepted = ~_refused(c2, z2, gv, gc)
          val () = let val verdict = (if same_file && c1_accepted && c2_accepted then "each accepted" else "one was refused"): string in println! ("controls: the unedited file, both texts replaced in the Dependabot spelling, both in the relock spelling: ", verdict) end
        in cut_1 && r1 && r2 && r3 && r4 && r5 && mr1 && mr2 && same_file && c1_accepted && c2_accepted end
      end
    end): bool
  val () = $A.drop<byte>(yf, yv)
  val () = $A.free<byte>($A.thaw<byte>(yf))
  val () = $A.drop<byte>(gf, gv)
  val () = $A.free<byte>($A.thaw<byte>(gf))
in ok end

(* ============================================================
   The flow of android.yml's steps
   ============================================================ *)

(* The steps in android.yml's order: attempt 1, the decision with attempt 1's outcome, the second attempt
   when the decision printed again=true. The status of the job: the decision's when it failed, else the last
   attempt's. It is 99, and the case fails, when the wiring check refuses the real android.yml *)
fn _flow {n:nat | n < 100} (name: string n): int =
  if ~_real_wired() then 99
  else let
    val first = _in_case(name, "bin/action", _no_arguments(), _no_arguments())
    val result = (if first = 0 then _decide(name, "success", "1", "2", "again=true", true)
      else _decide(name, "failure", "1", "2", "again=true", true)): @(int, bool)
    val @(decision, again) = result
  in
    if decision <> 0 then decision
    else if again then _in_case(name, "bin/action", _no_arguments(), _no_arguments())
    else first
  end

$UNITTEST.run begin

(* a cut-short manifest on the first call: two attempts, a pass *)
fn test_cut_then_whole (): bool = let
  val () = _fresh("cut-then-whole", 1, false)
  val status = _flow("cut-then-whole")
in status = 0 && size_of(_case_path("cut-then-whole", "calls")) = 2 end

(* the generated cases: every edit of every line of the block, by kind *)
fn test_edit_deleted_line_refused (): bool = _class("D", 0)
fn test_edit_changed_line_refused (): bool = _class("C", 1)
fn test_edit_added_line_refused (): bool = _class("I", 2)
fn test_edit_swapped_lines_refused (): bool = _class("S", 3)
fn test_cut_mask_and_controls (): bool = _cut_mask_controls()

(* a failure of the test after the emulator started is the job's failure and not run again *)
fn test_test_failure_not_run_again (): bool = let
  val () = _fresh("test-fails", 0, true)
  val status = _flow("test-fails")
in status = 1 && size_of(_case_path("test-fails", "calls")) = 1 end

(* the install fails on both attempts: two attempts, a failure *)
fn test_always_cut_fails (): bool = let
  val () = _fresh("always-cut", 2, false)
  val status = _flow("always-cut")
in status = 1 && size_of(_case_path("always-cut", "calls")) = 2 end

(* the decision on every input: the outcome (success, failure, another, none), the marker
   (there or not), the attempt (1 of 2, 2 of 2, 1 of 1) and the argument *)
fn _says {n:nat | n < 100}{o,l:nat | o < 100; l < 100}
  (name: string n, marker: bool, outcome: string o, attempt: string 1, attempts: string 1, status: int, line: string l): bool = let
  val () = _fresh(name, 0, false)
  val () = (if marker then let val _ = append_x(_case_path(name, "emulator-installed")) in () end else ())
  val @(code, said) = _decide(name, outcome, attempt, attempts, line, true)
in code = status && said end

fn test_decide_passed (): bool =
  _says("decide-passed", false, "success", "1", "2", 0, "again=false")
  && _says("decide-passed-marker", true, "success", "1", "2", 0, "again=false")

fn test_decide_retry (): bool =
  _says("decide-retry", false, "failure", "1", "2", 0, "again=true")

fn test_decide_test_verdict (): bool =
  _says("decide-verdict", true, "failure", "1", "2", 1, "again=false")

fn test_decide_no_attempt_left (): bool =
  _says("decide-last", false, "failure", "2", "2", 1, "again=false")
  && _says("decide-single", false, "failure", "1", "1", 1, "again=false")

fn test_decide_other_outcomes (): bool =
  _says("decide-cancelled", false, "cancelled", "1", "2", 1, "again=false")
  && _says("decide-skipped", false, "skipped", "1", "2", 1, "again=false")
  && _says("decide-empty", false, "", "1", "2", 1, "again=false")

fn test_decide_needs_marker_argument (): bool = let
  val () = _fresh("decide-usage", 0, false)
  val @(code, said) = _decide("decide-usage", "failure", "1", "2", "again=true", false)
in code = 2 && ~said end

end
