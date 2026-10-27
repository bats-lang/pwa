(* public_values -- gen-pwa values: writes a named JSON file of an app's public
   values, read from a committed env file, into dist/pwa (bats-lang/pwa#244,
   piece 2 of pwa#133, after gen-pwa pages of pwa#243). Build tooling for the
   app's CI: nothing here is part of what pwa generates or of what the app
   runs. The app names the env file, the output file and, for each value, its
   env name, its JSON key and its form; pwa holds no policy about which.

   gen-pwa values ENVFILE OUTFILE NAME:KEY:FORM...

   OUTFILE is one name under dist/pwa (not empty, not . or .., no slash).
   NAME is the env name of the value (letters, digits, underscore), KEY the
   JSON key (letters, digits, underscore, dash), FORM what the value must be:
   a sequence of items, each an atom with an optional count. An atom is a
   character (a backslash makes the next one literal) or a class in square
   brackets (characters and ranges a-z, a backslash makes the next one
   literal); a count is a plus (one or more) or braces ({n} or {m,n}); no
   count means exactly one. A class or character list is matched with
   backtracking, over the whole value. ENVFILE has plain NAME=value lines
   (any other line, as a comment or a blank, is not a value); a value is
   printable ASCII except the double quote and the backslash, so it needs no
   JSON escape.

   The file is {"KEY": "value", ...} and a newline, the keys in the order of
   the arguments, byte for byte what quire's scripts/sync-clients.sh wrote.
   Everything is checked before anything is written: a refusal says what and
   why on stderr, exits 1, and makes no file. A failed write says the path and
   the system's reason.

   Area note: .claude/rules/public-values.md (keyword: public-values). *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use env as E
#use file as F
#use result as R

(* What a run ended with; said where it happened, so no outcome carries
   data. ValuesChecked is the inside of a run (every value passed, nothing
   written yet), never an end. *)
datatype values_outcome =
  | ValuesWritten
  | ValuesChecked
  | ValuesUsage
  | ValuesArgumentsTooLong
  | ValuesOutputNameRefused
  | ValuesSpecRefused
  | ValuesEnvUnreadable
  | ValuesEnvTooLarge
  | ValuesValueMissing
  | ValuesValueRepeated
  | ValuesValueMalformed
  | ValuesOutputTooLarge
  | ValuesWriteFailed

(* How reading the env file ended *)
datatype env_read =
  | EnvEnded
  | EnvFailed
  | EnvTooBig

(* ============================================================
   Words to stderr
   ============================================================ *)

fn _say (s: string): void = prerr_string(s)

(* b[i, e) to stderr *)
fun _say_range {l:agz}{i:nat} .<max(524288 - i, 0)>.
  (b: !$A.borrow(byte, l, 524288), i: int i, e: int): void =
  if i >= e then ()
  else if i >= 524288 then ()
  else let
    val () = prerr_char(int2char0(byte2int0($A.read<byte>(b, i))))
  in _say_range(b, i + 1, e) end

fn _say_reason (e: $F.io_error): void = let
  val () = _say(": ")
  val () = _say($F.io_error_text(e))
in _say("\n") end

(* ============================================================
   Bytes
   ============================================================ *)

(* The byte at i, or minus one outside the buffer *)
fn _at {l:agz} (b: !$A.borrow(byte, l, 524288), i: int): int = let
  val j = g1ofg0(i)
in
  if j < 0 then ~1
  else if j >= 524288 then ~1
  else byte2int0($A.read<byte>(b, j))
end

fn _nat (x: int): [n:nat] int n = let
  val y = g1ofg0(x)
in if y >= 0 then y else 0 end

fn _put (out: !$B.builder_v >> $B.builder_v, v: int): void =
  if $B.length(out) < 524288 then $B.put_char(out, $AR.low_byte(v)) else ()

(* b[i, e) appended to out *)
fun _put_range {l:agz}{i:nat} .<max(524288 - i, 0)>.
  (b: !$A.borrow(byte, l, 524288), i: int i, e: int, out: !$B.builder_v >> $B.builder_v): void =
  if i >= e then ()
  else if i >= 524288 then ()
  else let
    val () = _put(out, byte2int0($A.read<byte>(b, i)))
  in _put_range(b, i + 1, e, out) end

(* The text s[j, n) appended to out *)
fun _put_text {sl:nat}{j:nat | j <= sl} .<sl - j>.
  (out: !$B.builder_v >> $B.builder_v, s: string sl, n: int sl, j: int j): void =
  if j >= n then ()
  else let val () = _put(out, char2int0(string_get_at(s, j))) in _put_text(out, s, n, j + 1) end

(* A path or a JSON text that fits: its length is below the builder's cap, so
   nothing was dropped by _put and a zero follows a path (to_arr zero-fills) *)
fn _fits (n: int): bool = n < 524288

(* ============================================================
   The arguments: NUL-separated in one buffer
   ============================================================ *)

(* The process's arguments into buf: their length *)
fn _args {l:agz} (buf: !$A.arr(byte, l, 524288)): int =
  case+ $E.args_read(buf, 524288) of
  | ~$R.some(k) => k
  | ~$R.none() => 0

(* Where the argument starting at i ends (its NUL), within k *)
fun _arg_end {l:agz}{i:nat} .<max(524288 - i, 0)>.
  (b: !$A.borrow(byte, l, 524288), i: int i, k: int): [e:nat | i <= e] int e =
  if i >= k then i
  else if i >= 524288 then i
  else if byte2int0($A.read<byte>(b, i)) = 0 then i
  else _arg_end(b, i + 1, k)

(* The first place in b[i, e) holding the byte ch, else e or more *)
fun _find_byte {l:agz}{i:nat} .<max(524288 - i, 0)>.
  (b: !$A.borrow(byte, l, 524288), i: int i, e: int, ch: int): [r:nat | i <= r] int r =
  if i >= e then i
  else if i >= 524288 then i
  else if byte2int0($A.read<byte>(b, i)) = ch then i
  else _find_byte(b, i + 1, e, ch)

(* Whether b[i, e) holds only letters, digits and
   underscores (and dashes when dash) *)
fun _word_chars {l:agz}{i:nat} .<max(524288 - i, 0)>.
  (b: !$A.borrow(byte, l, 524288), i: int i, e: int, dash: bool): bool =
  if i >= e then true
  else if i >= 524288 then false
  else let
    val c = byte2int0($A.read<byte>(b, i))
    val ok = ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
      || c = 95 || (dash && c = 45)): bool
  in if ok then _word_chars(b, i + 1, e, dash) else false end

(* Whether b[i, e) holds no slash *)
fun _no_slash {l:agz}{i:nat} .<max(524288 - i, 0)>.
  (b: !$A.borrow(byte, l, 524288), i: int i, e: int): bool =
  if i >= e then true
  else if i >= 524288 then false
  else if byte2int0($A.read<byte>(b, i)) = 47 then false
  else _no_slash(b, i + 1, e)

(* Whether b[s, e) can be a name under dist/pwa: not empty, not . or .., no slash *)
fn _name_ok {l:agz} (b: !$A.borrow(byte, l, 524288), s: int, e: int): bool =
  if e <= s then false
  else if e - s = 1 && _at(b, s) = 46 then false
  else if e - s = 2 && _at(b, s) = 46 && _at(b, s + 1) = 46 then false
  else _no_slash(b, _nat(s), e)

(* Whether b[i, e) is printable ASCII without the double quote and the
   backslash: a JSON string with no escape *)
fun _plain_value {l:agz}{i:nat} .<max(524288 - i, 0)>.
  (b: !$A.borrow(byte, l, 524288), i: int i, e: int): bool =
  if i >= e then true
  else if i >= 524288 then false
  else let
    val c = byte2int0($A.read<byte>(b, i))
  in
    if c < 32 || c > 126 || c = 34 || c = 92 then false
    else _plain_value(b, i + 1, e)
  end

(* ============================================================
   A form: items of an atom and a count, matched with backtracking
   ============================================================ *)

(* The character of a class at j and how many bytes it takes: a backslash
   makes the next byte literal *)
fn _class_char {l:agz} (b: !$A.borrow(byte, l, 524288), j: int): @(int, [w:pos] int w) =
  if _at(b, j) = 92 then @(_at(b, j + 1), 2) else @(_at(b, j), 1)

(* Whether ch is in the class b[j, ce): characters and ranges lo-hi *)
fun _in_class {l:agz}{j:nat} .<max(524288 - j, 0)>.
  (b: !$A.borrow(byte, l, 524288), j: int j, ce: int, ch: int): bool =
  if j >= ce then false
  else if j >= 524288 then false
  else let
    val @(lo, w1) = _class_char(b, j)
    val n1 = j + w1
  in
    if n1 + 1 < ce && _at(b, n1) = 45 then let
      val @(hi, w2) = _class_char(b, n1 + 1)
    in
      if lo <= ch && ch <= hi then true
      else _in_class(b, n1 + 1 + w2, ce, ch)
    end
    else if ch = lo then true
    else _in_class(b, n1, ce, ch)
  end

(* The closing bracket of a class whose characters start at j, within pe, else minus one *)
fun _class_close {l:agz}{j:nat} .<max(524288 - j, 0)>.
  (b: !$A.borrow(byte, l, 524288), j: int j, pe: int): int =
  if j >= pe then ~1
  else if j >= 524288 then ~1
  else let
    val c = byte2int0($A.read<byte>(b, j))
  in
    if c = 93 then j
    else if c = 92 then (if j + 1 < pe then _class_close(b, j + 2, pe) else ~1)
    else _class_close(b, j + 1, pe)
  end

(* Where the atom starting at i ends, within pe, else minus one: a class
   (not empty), a backslash and a byte, or a byte that is not one of the
   marks of a count or a class (the plus, the braces, the closing bracket, the
   question mark, the star) *)
fn _atom_end {l:agz} (b: !$A.borrow(byte, l, 524288), i: int, pe: int): int = let
  val c = _at(b, i)
in
  if c = 91 then let
    val close = _class_close(b, _nat(i + 1), pe)
  in if close <= i + 1 then ~1 else close + 1 end
  else if c = 92 then (if i + 1 < pe then i + 2 else ~1)
  else if c = 93 || c = 43 || c = 123 || c = 125 || c = 63 || c = 42 then ~1
  else i + 1
end

(* The digits at i: their value, how many (nine for more than eight) and
   where they end *)
fun _digits {l:agz}{d:nat | d <= 8} .<8 - d>.
  (b: !$A.borrow(byte, l, 524288), i: int, pe: int, acc: int, d: int d): @(int, int, int) =
  if i >= pe then @(acc, d, i)
  else let
    val c = _at(b, i)
  in
    if c >= 48 && c <= 57 then
      (if d >= 8 then @(acc, 9, i) else _digits(b, i + 1, pe, acc * 10 + (c - 48), d + 1))
    else @(acc, d, i)
  end

(* The count after an atom that ends at ae: least, most and where it ends,
   else minus one for where *)
fn _count {l:agz} (b: !$A.borrow(byte, l, 524288), ae: int, pe: int): @(int, int, int) =
  if ae >= pe then @(1, 1, ae)
  else let
    val c = _at(b, ae)
  in
    if c = 43 then @(1, 524288, ae + 1)
    else if c = 123 then let
      val @(least, d1, p1) = _digits(b, ae + 1, pe, 0, 0)
    in
      if d1 = 0 || d1 > 8 then @(0, 0, ~1)
      else if p1 < pe && _at(b, p1) = 125 then @(least, least, p1 + 1)
      else if p1 < pe && _at(b, p1) = 44 then let
        val @(most, d2, p2) = _digits(b, p1 + 1, pe, 0, 0)
      in
        if d2 = 0 || d2 > 8 then @(0, 0, ~1)
        else if p2 < pe && _at(b, p2) = 125 && least <= most then @(least, most, p2 + 1)
        else @(0, 0, ~1)
      end
      else @(0, 0, ~1)
    end
    else @(1, 1, ae)
  end

(* Whether b[pi, pe) is a form *)
fun _form_ok {l:agz}{pi:nat} .<max(524288 - pi, 0)>.
  (b: !$A.borrow(byte, l, 524288), pi: int pi, pe: int): bool =
  if pi >= pe then true
  else if pi >= 524288 then false
  else let
    val ae = _atom_end(b, pi, pe)
  in
    if ae < 0 then false
    else let
      val @(_, _, np) = _count(b, ae, pe)
      val np1 = g1ofg0(np)
    in
      if np1 <= pi then false else _form_ok(b, np1, pe)
    end
  end

(* Whether the byte ch is what the atom a0 to a1 stands for *)
fn _atom_has {l:agz} (b: !$A.borrow(byte, l, 524288), a0: int, a1: int, ch: int): bool = let
  val c = _at(b, a0)
in
  if c = 91 then _in_class(b, _nat(a0 + 1), a1 - 1, ch)
  else if c = 92 then ch = _at(b, a0 + 1)
  else ch = c
end

(* How many bytes from vi, at most lim, the atom a0 to a1 takes in a row, from n *)
fun _run {lp,lv:agz}{n,lim:nat | n <= lim} .<lim - n>.
  (pb: !$A.borrow(byte, lp, 524288), a0: int, a1: int,
   vb: !$A.borrow(byte, lv, 524288), vi: int, ve: int, n: int n, lim: int lim)
  : [r:nat | r <= lim] int r =
  if n >= lim then n
  else if vi + n >= ve then n
  else if _atom_has(pb, a0, a1, _at(vb, vi + n)) then _run(pb, a0, a1, vb, vi, ve, n + 1, lim)
  else n

(* Whether the form pb[pi, pe) matches all of vb[vi, ve) *)
fun _form_from {lp,lv:agz}{pi:nat} .<max(524288 - pi, 0), 1, 0>.
  (pb: !$A.borrow(byte, lp, 524288), pi: int pi, pe: int,
   vb: !$A.borrow(byte, lv, 524288), vi: int, ve: int): bool =
  if pi >= pe then vi = ve
  else if pi >= 524288 then false
  else let
    val ae = _atom_end(pb, pi, pe)
  in
    if ae < 0 then false
    else let
      val @(least, most, np) = _count(pb, ae, pe)
      val np1 = g1ofg0(np)
    in
      if np1 <= pi then false
      else let
        val room = (if most < ve - vi then most else ve - vi): int
        val got = _run(pb, pi, ae, vb, vi, ve, 0, _nat(room))
      in _form_counts(pb, pi, np1, pe, vb, vi, ve, least, got) end
    end
  end

(* The same, the atom taking c bytes or fewer, down to least *)
and _form_counts {lp,lv:agz}{pi,j:nat | pi < 524288; pi < j}{c:nat} .<max(524288 - pi, 0), 0, c>.
  (pb: !$A.borrow(byte, lp, 524288), pi: int pi, j: int j, pe: int,
   vb: !$A.borrow(byte, lv, 524288), vi: int, ve: int, least: int, c: int c): bool =
  if c < least then false
  else if _form_from(pb, j, pe, vb, vi + c, ve) then true
  else if c <= 0 then false
  else _form_counts(pb, pi, j, pe, vb, vi, ve, least, c - 1)

(* ============================================================
   The env file: plain NAME=value lines
   ============================================================ *)

(* Where the line starting at i ends (its newline), within ek *)
fun _line_end {l:agz}{i:nat} .<max(524288 - i, 0)>.
  (b: !$A.borrow(byte, l, 524288), i: int i, ek: int): [e:nat | i <= e] int e =
  if i >= ek then i
  else if i >= 524288 then i
  else if byte2int0($A.read<byte>(b, i)) = 10 then i
  else _line_end(b, i + 1, ek)

(* Whether eb at line starts with the len bytes of nb at ns and an equals sign *)
fun _has_prefix {le,ln:agz}{t:nat} .<max(524288 - t, 0)>.
  (eb: !$A.borrow(byte, le, 524288), line: int,
   nb: !$A.borrow(byte, ln, 524288), ns: int, len: int, t: int t): bool =
  if t >= len then _at(eb, line + len) = 61
  else if t >= 524288 then false
  else if _at(eb, line + t) = _at(nb, ns + t) then _has_prefix(eb, line, nb, ns, len, t + 1)
  else false

(* How many lines of eb[i, ek) are NAME=value for the len bytes of nb at ns,
   and the start and end of the value of the first *)
fun _lookup {le,ln:agz}{i:nat} .<max(524288 - i, 0)>.
  (eb: !$A.borrow(byte, le, 524288), ek: int, i: int i,
   nb: !$A.borrow(byte, ln, 524288), ns: int, len: int,
   count: int, vs: int, ve: int): @(int, int, int) =
  if i >= ek then @(count, vs, ve)
  else if i >= 524288 then @(count, vs, ve)
  else let
    val le = _line_end(eb, i, ek)
  in
    if _has_prefix(eb, i, nb, ns, len, 0) then
      (if count = 0 then _lookup(eb, ek, le + 1, nb, ns, len, 1, i + len + 1, le)
       else _lookup(eb, ek, le + 1, nb, ns, len, count + 1, vs, ve))
    else _lookup(eb, ek, le + 1, nb, ns, len, count, vs, ve)
  end

(* The env file read to its end into out, 4096 bytes at a time. Each read
   adds at least one byte, so fuel (a byte a read, the builder's cap and one
   more) bounds the loop; a file of 524288 bytes or more is EnvTooBig. *)
fun _put_chunk {lc:agz}{i:nat} .<max(4096 - i, 0)>.
  (chunk: !$A.arr(byte, lc, 4096), i: int i, k: int, out: !$B.builder_v >> $B.builder_v): void =
  if i >= k then ()
  else if i >= 4096 then ()
  else let
    val () = _put(out, byte2int0($A.get<byte>(chunk, i)))
  in _put_chunk(chunk, i + 1, k, out) end

fun _read_chunks {lp,lc:agz}{f:nat} .<f>.
  (ep: !$A.borrow(byte, lp, 524288), epk: int, src: !$F.fd, chunk: !$A.arr(byte, lc, 4096), out: !$B.builder_v >> $B.builder_v,
   fuel: int f): env_read =
  if fuel <= 0 then EnvTooBig()
  else if not(_fits($B.length(out))) then EnvTooBig()
  else
    case+ $F.file_read(src, chunk, 4096) of
    | ~$R.err(e) => let
        val () = _say("gen-pwa values: ")
        val () = _say_range(ep, 0, epk)
        val () = _say_reason(e)
      in EnvFailed() end
    | ~$R.ok(k) =>
        if k <= 0 then EnvEnded()
        else let
          val () = _put_chunk(chunk, 0, k, out)
        in _read_chunks(ep, epk, src, chunk, out, fuel - 1) end

(* ============================================================
   Checking each NAME:KEY:FORM against the env file
   ============================================================ *)

fn _say_spec {l:agz} (b: !$A.borrow(byte, l, 524288), s: int, e: int, what: string): void = let
  val () = _say("gen-pwa values: ")
  val () = _say_range(b, _nat(s), e)
  val () = _say(": ")
  val () = _say(what)
in _say("\n") end

(* The specs from s on: each is checked against eb (the env file, ek bytes)
   and, when it passes, appended to js as "KEY": "value". The first that
   fails ends the check, said with its name and why. *)
fun _spec_pass {la,le:agz}{s,es:nat} .<max(524288 - s, 0)>.
  (ab: !$A.borrow(byte, la, 524288), ak: int,
   eb: !$A.borrow(byte, le, 524288), ek: int,
   js: !$B.builder_v >> $B.builder_v, s: int s, index: int, env_s: int es, env_e: int): values_outcome =
  if s >= ak then ValuesChecked()
  else if s >= 524288 then ValuesArgumentsTooLong()
  else let
    val se = _arg_end(ab, s, ak)
    val c1 = _find_byte(ab, s, se, 58)
    val c2 = _find_byte(ab, c1 + 1, se, 58)
  in
    if c1 >= se || c2 >= se then let
      val () = _say_spec(ab, s, se, "not NAME:KEY:FORM")
    in ValuesSpecRefused() end
    else if c1 <= s || not(_word_chars(ab, s, c1, false)) then let
      val () = _say_spec(ab, s, se, "NAME must be letters, digits and underscores, not empty")
    in ValuesSpecRefused() end
    else if c2 <= c1 + 1 || not(_word_chars(ab, c1 + 1, c2, true)) then let
      val () = _say_spec(ab, s, se, "KEY must be letters, digits, underscores and dashes, not empty")
    in ValuesSpecRefused() end
    else if c2 + 1 >= se then let
      val () = _say_spec(ab, s, se, "FORM is empty")
    in ValuesSpecRefused() end
    else if not(_form_ok(ab, c2 + 1, se)) then let
      val () = _say_spec(ab, s, se, "FORM is not a form (an atom, a class in brackets, a count of plus or braces)")
    in ValuesSpecRefused() end
    else let
      val @(count, vs, ve) = _lookup(eb, ek, 0, ab, s, c1 - s, 0, 0, 0)
    in
      if count <= 0 then let
        val () = _say("gen-pwa values: ")
        val () = _say_range(ab, s, c1)
        val () = _say(": no line NAME=value in ")
        val () = _say_range(ab, env_s, env_e)
        val () = _say("\n")
      in ValuesValueMissing() end
      else if count >= 2 then let
        val () = _say("gen-pwa values: ")
        val () = _say_range(ab, s, c1)
        val () = _say(": more than one line NAME=value in ")
        val () = _say_range(ab, env_s, env_e)
        val () = _say("\n")
      in ValuesValueRepeated() end
      else if not(_plain_value(eb, _nat(vs), ve)) then let
        val () = _say("gen-pwa values: ")
        val () = _say_range(ab, s, c1)
        val () = _say(" in ")
        val () = _say_range(ab, env_s, env_e)
        val () = _say(": the value has a character other than printable ASCII, or a double quote or a backslash\n")
      in ValuesValueMalformed() end
      else if not(_form_from(ab, c2 + 1, se, eb, vs, ve)) then let
        val () = _say("gen-pwa values: ")
        val () = _say_range(ab, s, c1)
        val () = _say(" in ")
        val () = _say_range(ab, env_s, env_e)
        val () = _say(": the value is not of the form ")
        val () = _say_range(ab, c2 + 1, se)
        val () = _say("\n")
      in ValuesValueMalformed() end
      else let
        val from = (if index = 0 then 2 else 0): [j:nat | j <= 2] int j
        val () = _put_text(js, ", ", 2, from)
        val () = _put(js, 34)
        val () = _put_range(ab, c1 + 1, c2, js)
        val () = _put_text(js, "\": \"", 4, 0)
        val () = _put_range(eb, _nat(vs), ve, js)
        val () = _put_text(js, "\"", 1, 0)
      in _spec_pass(ab, ak, eb, ek, js, se + 1, index + 1, env_s, env_e) end
    end
  end

(* ============================================================
   Writing the file
   ============================================================ *)

(* The n bytes of a to the file at the path op (target_len bytes, a zero after),
   made or emptied with mode 0644 *)
fn _write_json {lo:agz}{l:agz}{n:nat | n <= 524288}
  (target: !$A.borrow(byte, lo, 524288), target_len: int,
   a: $A.arr(byte, l, 524288), n: int n): values_outcome = let
  val @(fz, bv) = $A.freeze<byte>(a)
  val @(left, right) = $A.borrow_split<byte>(fz, bv, n)
  val out = (case+ $F.file_open(target, 524288, $F.WriteOnly(), $F.CreateOrTruncate(), 420) of
    | ~$R.err(e) => let
        val () = _say("gen-pwa values: ")
        val () = _say_range(target, 0, target_len)
        val () = _say_reason(e)
      in ValuesWriteFailed() end
    | ~$R.ok(dst) => let
        val wrote = (if n >= 1 then (case+ $F.file_write(dst, left, n) of
            | ~$R.err(e) => let
                val () = _say("gen-pwa values: ")
                val () = _say_range(target, 0, target_len)
                val () = _say_reason(e)
              in ValuesWriteFailed() end
            | ~$R.ok(_) => ValuesWritten())
          else ValuesWritten()): values_outcome
      in
        case+ $F.file_close(dst) of
        | ~$R.err(e) => (case+ wrote of
            | ValuesWritten() => let
                val () = _say("gen-pwa values: ")
                val () = _say_range(target, 0, target_len)
                val () = _say_reason(e)
              in ValuesWriteFailed() end
            | _ => wrote)
        | ~$R.ok(_) => wrote
      end): values_outcome
  val () = $A.drop<byte>(fz, $A.borrow_join<byte>(fz, left, right))
  val () = $A.free<byte>($A.thaw<byte>(fz))
in out end

(* ============================================================
   gen-pwa values ENVFILE OUTFILE NAME:KEY:FORM...
   ============================================================ *)

(* Everything is read and checked before the output file is opened *)
fn _values_with_env {la,lp,lo:agz}
  (ab: !$A.borrow(byte, la, 524288), ak: int, specs: int, env_s: int, env_e: int,
   ep: !$A.borrow(byte, lp, 524288), epk: int,
   target: !$A.borrow(byte, lo, 524288), target_len: int): values_outcome =
  case+ $F.file_open(ep, 524288, $F.ReadOnly(), $F.OpenExisting(), 0) of
  | ~$R.err(e) => let
      val () = _say("gen-pwa values: ")
      val () = _say_range(ep, 0, epk)
      val () = _say_reason(e)
    in ValuesEnvUnreadable() end
  | ~$R.ok(src) => let
      var envb : $B.builder_v = $B.create()
      val chunk = $A.alloc<byte>(4096)
      val read = _read_chunks(ep, epk, src, chunk, envb, 524289)
      val () = $A.free<byte>(chunk)
      val () = $R.discard<int><$F.io_error>($F.file_close(src))
      val @(ea, ek) = $B.to_arr(envb)
    in
      case+ read of
      | EnvEnded() => let
          val @(efz, ebv) = $A.freeze<byte>(ea)
          var js : $B.builder_v = $B.create()
          val () = _put_text(js, "{", 1, 0)
          val checked = _spec_pass(ab, ak, ebv, ek, js, _nat(specs), 0, _nat(env_s), env_e)
          val () = (case+ checked of
            | ValuesChecked() => _put_text(js, "}\n", 2, 0)
            | _ => ())
          val @(ja, jk) = $B.to_arr(js)
          val out = (case+ checked of
            | ValuesChecked() =>
                if _fits(jk) then _write_json(target, target_len, ja, jk)
                else let
                  val () = $A.free<byte>(ja)
                  val () = _say("gen-pwa values: the file would be 524288 bytes or more\n")
                in ValuesOutputTooLarge() end
            | _ => let val () = $A.free<byte>(ja) in checked end): values_outcome
          val () = $A.drop<byte>(efz, ebv)
          val () = $A.free<byte>($A.thaw<byte>(efz))
        in out end
      | EnvTooBig() => let
          val () = $A.free<byte>(ea)
          val () = _say("gen-pwa values: ")
          val () = _say_range(ep, 0, epk)
          val () = _say(": 524288 bytes or more, too large for an env file\n")
        in ValuesEnvTooLarge() end
      | EnvFailed() => let
          val () = $A.free<byte>(ea)
        in ValuesEnvUnreadable() end
    end

fn _values_with_args {l:agz} (b: !$A.borrow(byte, l, 524288), k: int): values_outcome = let
  val e0 = _arg_end(b, 0, k)
  val e1 = _arg_end(b, e0 + 1, k)
  val e2 = _arg_end(b, e1 + 1, k)
  val e3 = _arg_end(b, e2 + 1, k)
in
  if k >= 524288 then let
    val () = _say("gen-pwa values: the arguments are 524288 bytes or more\n")
  in ValuesArgumentsTooLong() end
  else if e3 + 1 >= k then let
    val () = _say("usage: gen-pwa values ENVFILE OUTFILE NAME:KEY:FORM...\n")
  in ValuesUsage() end
  else if not(_name_ok(b, e2 + 1, e3)) then let
    val () = _say("gen-pwa values: OUTFILE must be one name under dist/pwa: not empty, not . or .., no slash\n")
  in ValuesOutputNameRefused() end
  else let
    var eb : $B.builder_v = $B.create()
    val () = _put_range(b, e1 + 1, e2, eb)
    var ob : $B.builder_v = $B.create()
    val () = _put_text(ob, "dist/pwa/", 9, 0)
    val () = _put_range(b, e2 + 1, e3, ob)
    val @(ea, epk) = $B.to_arr(eb)
    val @(oa, target_len) = $B.to_arr(ob)
    val @(efz, ebv) = $A.freeze<byte>(ea)
    val @(ofz, obv) = $A.freeze<byte>(oa)
    val out = (if not(_fits(epk)) then let
        val () = _say("gen-pwa values: the env file path is 524288 bytes or more\n")
      in ValuesArgumentsTooLong() end
      else if not(_fits(target_len)) then let
        val () = _say("gen-pwa values: the output path is 524288 bytes or more\n")
      in ValuesArgumentsTooLong() end
      else _values_with_env(b, k, e3 + 1, e1 + 1, e2, ebv, epk, obv, target_len)): values_outcome
    val () = $A.drop<byte>(efz, ebv)
    val () = $A.free<byte>($A.thaw<byte>(efz))
    val () = $A.drop<byte>(ofz, obv)
    val () = $A.free<byte>($A.thaw<byte>(ofz))
  in out end
end

#pub fn values_wanted (): bool

#pub fn values_run (): int

implement values_wanted () = let
  val buf = $A.alloc<byte>(524288)
  val k = _args(buf)
  val @(fz, bv) = $A.freeze<byte>(buf)
  val s = _arg_end(bv, 0, k) + 1
  val e = _arg_end(bv, s, k)
  val wanted = (e - s = 6 && s < k && _at(bv, s) = 118 && _at(bv, s + 1) = 97
    && _at(bv, s + 2) = 108 && _at(bv, s + 3) = 117 && _at(bv, s + 4) = 101
    && _at(bv, s + 5) = 115): bool
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in wanted end

implement values_run () = let
  val buf = $A.alloc<byte>(524288)
  val k = _args(buf)
  val @(fz, bv) = $A.freeze<byte>(buf)
  val out = _values_with_args(bv, k)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in
  case+ out of
  | ValuesWritten() => 0
  | _ => 1
end
