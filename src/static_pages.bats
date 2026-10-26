(* static_pages -- gen-pwa pages: copies a directory of an app's static
   pages into dist/pwa (bats-lang/pwa#243, piece 1 of pwa#133). Build
   tooling for the app's CI: nothing here is part of what pwa generates or
   of what the app runs, and the app names the directory and the name.

   gen-pwa pages SOURCE NAME

   copies the tree at SOURCE, files byte for byte, to dist/pwa/NAME. It is
   refused, said with its reason, exit 1, and nothing is written when:
   the arguments are not exactly SOURCE and NAME (or are too long); NAME is
   empty, is . or .., or holds a slash (so it cannot leave dist/pwa);
   SOURCE is not a readable directory. After those, dist/pwa/NAME is made
   by mkdir, so a destination that exists is refused by the system's own
   answer (EEXIST) and nothing of it is touched. A read or a write that
   fails while copying says the path and the system's reason, and stops.

   Area note: .claude/rules/static-pages.md (keyword: static-pages). *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use env as E
#use file as F
#use result as R

(* What a run ended with; said where it happened, with the path and the
   system's reason, so no outcome carries data *)
datatype pages_outcome =
  | PagesCopied
  | PagesUsage
  | PagesNameRefused
  | PagesSourceRefused
  | PagesDestinationExists
  | PagesReadFailed
  | PagesWriteFailed
  | PagesPathTooLong
  | PagesTooDeep

(* The most levels of directories a tree may have: a symbolic link that
   loops is refused after this many instead of followed for ever *)
#define PAGES_DEPTH 64

(* ============================================================
   Words to stderr
   ============================================================ *)

fn _say (s: string): void = prerr_string(s)

(* b[0, k) to stderr *)
fun _say_bytes {l:agz}{i:nat} .<max(524288 - i, 0)>.
  (b: !$A.borrow(byte, l, 524288), i: int i, k: int): void =
  if i >= k then ()
  else if i >= 524288 then ()
  else let
    val () = prerr_char(int2char0(byte2int0($A.read<byte>(b, i))))
  in _say_bytes(b, i + 1, k) end

fn _say_path {l:agz} (b: !$A.borrow(byte, l, 524288), k: int): void = let
  val () = _say("gen-pwa pages: ")
in _say_bytes(b, 0, k) end

fn _say_reason (e: $F.io_error): void = let
  val () = _say(": ")
  val () = _say($F.io_error_text(e))
in _say("\n") end

(* ============================================================
   Paths: bytes, a length, and the zero after them
   ============================================================ *)

fn _put (out: !$B.builder_v >> $B.builder_v, v: int): void =
  if $B.length(out) < 524288 then $B.put_char(out, $AR.low_byte(v)) else ()

(* b[i, k) appended to out *)
fun _put_range {l:agz}{i:nat} .<max(524288 - i, 0)>.
  (b: !$A.borrow(byte, l, 524288), i: int i, k: int, out: !$B.builder_v >> $B.builder_v): void =
  if i >= k then ()
  else if i >= 524288 then ()
  else let
    val () = _put(out, byte2int0($A.read<byte>(b, i)))
  in _put_range(b, i + 1, k, out) end

(* name[0, k) appended to out *)
fun _put_name {l:agz}{i:nat} .<max(1024 - i, 0)>.
  (name: !$A.arr(byte, l, 1024), i: int i, k: int, out: !$B.builder_v >> $B.builder_v): void =
  if i >= k then ()
  else if i >= 1024 then ()
  else let
    val () = _put(out, byte2int0($A.get<byte>(name, i)))
  in _put_name(name, i + 1, k, out) end

(* A path that fits: its length is below the builder's cap, so the byte
   after it is a zero (to_arr zero-fills). A length at the cap means _put
   may have dropped bytes, so it is refused, never used. *)
fn _fits (n: int): bool = n < 524288

(* ============================================================
   Operations on a path (a borrow of 524288 bytes, zero after the path)
   ============================================================ *)

fn _mkdir {l:agz} (p: !$A.borrow(byte, l, 524288)): $R.result(int, $F.io_error) =
  $F.file_mkdir(p, 524288, 493)

(* The mode to give a copy: the source's permission bits, else 0644 *)
fn _mode_of {l:agz} (p: !$A.borrow(byte, l, 524288)): int =
  case+ $F.file_mode(p, 524288) of
  | ~$R.ok(m) => m
  | ~$R.err(_) => 420

(* Whether the path is a directory: yes, no (it opens as a file would), or
   why it cannot be told *)
datatype kind =
  | KindDirectory
  | KindOther
  | KindUnreadable of ()

fn _kind_of {l:agz} (p: !$A.borrow(byte, l, 524288), k: int): kind =
  case+ $F.dir_open(p, 524288) of
  | ~$R.ok(d) => let
      val () = $R.discard<int><$F.io_error>($F.dir_close(d))
    in KindDirectory() end
  | ~$R.err(e) => (case+ e of
      | $F.NotADirectory() => KindOther()
      | _ => let
          val () = _say_path(p, k)
          val () = _say_reason(e)
        in KindUnreadable() end)

(* ============================================================
   Copying a file
   ============================================================ *)

(* The bytes of sp to dp, dp made with sp's permission bits *)
fn _copy_file {ls,ld:agz} (sp: !$A.borrow(byte, ls, 524288), sk: int,
  dp: !$A.borrow(byte, ld, 524288), dk: int): pages_outcome =
  case+ $F.file_open(sp, 524288, $F.ReadOnly(), $F.OpenExisting(), 0) of
  | ~$R.err(e) => let
      val () = _say_path(sp, sk)
      val () = _say_reason(e)
    in PagesReadFailed() end
  | ~$R.ok(src) => let
      val mode = _mode_of(sp)
      val out = (case+ $F.file_open(dp, 524288, $F.WriteOnly(), $F.CreateOrTruncate(), mode) of
        | ~$R.err(e) => let
            val () = _say_path(dp, dk)
            val () = _say_reason(e)
          in PagesWriteFailed() end
        | ~$R.ok(dst) => let
            val copied = $F.fd_copy(src, dst)
            val closed = $F.file_close(dst)
          in
            case+ copied of
            | ~$R.err(e) => let
                val () = _say_path(sp, sk)
                val () = _say(" to ")
                val () = _say_bytes(dp, 0, dk)
                val () = _say_reason(e)
                val () = $R.discard<int><$F.io_error>(closed)
              in PagesWriteFailed() end
            | ~$R.ok(_) => (case+ closed of
                | ~$R.err(e) => let
                    val () = _say_path(dp, dk)
                    val () = _say_reason(e)
                  in PagesWriteFailed() end
                | ~$R.ok(_) => PagesCopied())
          end): pages_outcome
      val () = $R.discard<int><$F.io_error>($F.file_close(src))
    in out end

(* ============================================================
   Copying a directory, level by level
   ============================================================ *)

fn _is_dot {l:agz} (name: !$A.arr(byte, l, 1024), k: int): bool =
  if k = 1 then byte2int0($A.get<byte>(name, 0)) = 46
  else if k = 2 then
    (byte2int0($A.get<byte>(name, 0)) = 46 && byte2int0($A.get<byte>(name, 1)) = 46)
  else false

(* The path of a child of the directory at p (length pk): p, a slash and
   the name, as a borrow's owner; its length is returned with it *)
fn _child {l:agz}{ln:agz} (p: !$A.borrow(byte, l, 524288), pk: int,
  name: !$A.arr(byte, ln, 1024), nk: int): @([lc:agz] $A.arr(byte, lc, 524288), int) = let
  var b : $B.builder_v = $B.create()
  val () = _put_range(p, 0, pk, b)
  val () = _put(b, 47)
  val () = _put_name(name, 0, nk, b)
  val @(a, k) = $B.to_arr(b)
in @(a, k) end

fun copy_dir {ls,ld:agz}{d:nat} .<d, 2, 0>.
  (sp: !$A.borrow(byte, ls, 524288), sk: int,
   dp: !$A.borrow(byte, ld, 524288), dk: int, fuel: int d): pages_outcome =
  case+ $F.dir_read(sp, 524288) of
  | ~$R.err(e) => let
      val () = _say_path(sp, sk)
      val () = _say_reason(e)
    in PagesReadFailed() end
  | ~$R.ok(es) => let
      val name = $A.alloc<byte>(1024)
      val n = $F.entries_count(es)
      val out = copy_entries(sp, sk, dp, dk, es, name, 0, n, fuel)
      val () = $A.free<byte>(name)
      val () = $F.entries_free(es)
    in out end

and copy_entries {ls,ld:agz}{ln:agz}{k:nat}{i:nat | i <= k}{d:nat} .<d, 1, k - i>.
  (sp: !$A.borrow(byte, ls, 524288), sk: int,
   dp: !$A.borrow(byte, ld, 524288), dk: int,
   es: !$F.entries(k), name: !$A.arr(byte, ln, 1024), i: int i, n: int k, fuel: int d): pages_outcome =
  if i >= n then PagesCopied()
  else let
    val nk = $F.entries_name(es, i, name, 1024)
  in
    if _is_dot(name, nk) then copy_entries(sp, sk, dp, dk, es, name, i + 1, n, fuel)
    else let
      val out = copy_entry(sp, sk, dp, dk, name, nk, fuel)
    in
      case+ out of
      | PagesCopied() => copy_entries(sp, sk, dp, dk, es, name, i + 1, n, fuel)
      | _ => out
    end
  end

and copy_entry {ls,ld:agz}{ln:agz}{d:nat} .<d, 0, 0>.
  (sp: !$A.borrow(byte, ls, 524288), sk: int,
   dp: !$A.borrow(byte, ld, 524288), dk: int,
   name: !$A.arr(byte, ln, 1024), nk: int, fuel: int d): pages_outcome = let
  val @(sa, sk2) = _child(sp, sk, name, nk)
  val @(da, dk2) = _child(dp, dk, name, nk)
  val @(sfz, sbv) = $A.freeze<byte>(sa)
  val @(dfz, dbv) = $A.freeze<byte>(da)
  val out = (if not(_fits(sk2)) then let
      val () = _say_path(sp, sk)
      val () = _say("/...: a path of 524288 bytes or more\n")
    in PagesPathTooLong() end
    else if not(_fits(dk2)) then let
      val () = _say_path(dp, dk)
      val () = _say("/...: a path of 524288 bytes or more\n")
    in PagesPathTooLong() end
    else (case+ _kind_of(sbv, sk2) of
      | KindUnreadable() => PagesReadFailed()
      | KindOther() => _copy_file(sbv, sk2, dbv, dk2)
      | KindDirectory() =>
          if fuel <= 0 then let
            val () = _say_path(sbv, sk2)
            val () = _say(": more than 64 levels of directories (a link that loops?)\n")
          in PagesTooDeep() end
          else (case+ _mkdir(dbv) of
            | ~$R.err(e) => let
                val () = _say_path(dbv, dk2)
                val () = _say_reason(e)
              in PagesWriteFailed() end
            | ~$R.ok(_) => copy_dir(sbv, sk2, dbv, dk2, fuel - 1)))): pages_outcome
  val () = $A.drop<byte>(sfz, sbv)
  val () = $A.free<byte>($A.thaw<byte>(sfz))
  val () = $A.drop<byte>(dfz, dbv)
  val () = $A.free<byte>($A.thaw<byte>(dfz))
in out end

(* ============================================================
   gen-pwa pages SOURCE NAME
   ============================================================ *)

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

(* The byte at i, or minus one outside the buffer *)
fn _at {l:agz} (b: !$A.borrow(byte, l, 4096), i: int): int = let
  val j = g1ofg0(i)
in
  if j < 0 then ~1
  else if j >= 4096 then ~1
  else byte2int0($A.read<byte>(b, j))
end

(* b[i, e) appended to out *)
fun _put_args {l:agz}{i:nat} .<max(4096 - i, 0)>.
  (b: !$A.borrow(byte, l, 4096), i: int i, e: int, out: !$B.builder_v >> $B.builder_v): void =
  if i >= e then ()
  else if i >= 4096 then ()
  else let
    val () = _put(out, byte2int0($A.read<byte>(b, i)))
  in _put_args(b, i + 1, e, out) end

fn _nat (x: int): [n:nat] int n = let
  val y = g1ofg0(x)
in if y >= 0 then y else 0 end

(* Whether b[i, e) holds no slash *)
fun _no_slash {l:agz}{i:nat} .<max(4096 - i, 0)>.
  (b: !$A.borrow(byte, l, 4096), i: int i, e: int): bool =
  if i >= e then true
  else if i >= 4096 then false
  else if byte2int0($A.read<byte>(b, i)) = 47 then false
  else _no_slash(b, i + 1, e)

(* Whether b[s, e) can be a name under dist/pwa: not empty, not . or .., no slash *)
fn _name_ok {l:agz} (b: !$A.borrow(byte, l, 4096), s: int, e: int): bool =
  if e <= s then false
  else if e - s = 1 && _at(b, s) = 46 then false
  else if e - s = 2 && _at(b, s) = 46 && _at(b, s + 1) = 46 then false
  else _no_slash(b, _nat(s), e)

(* The path in a builder (consumed) as a borrowed array, for f's call *)
fn _run_copy {l:agz} (b: !$A.borrow(byte, l, 4096), ss: int, se: int, ns: int, ne: int): pages_outcome = let
  var sb : $B.builder_v = $B.create()
  val () = _put_args(b, _nat(ss), se, sb)
  var db : $B.builder_v = $B.create()
  val () = (let
    val dir = "dist/pwa/"
    fun loop {sl:nat}{j:nat | j <= sl} .<sl - j>.
      (out: !$B.builder_v >> $B.builder_v, s: string sl, n: int sl, j: int j): void =
      if j >= n then ()
      else let val () = _put(out, char2int0(string_get_at(s, j))) in loop(out, s, n, j + 1) end
  in loop(db, dir, g1u2i(string1_length(dir)), 0) end)
  val () = _put_args(b, _nat(ns), ne, db)
  val @(sa, sk) = $B.to_arr(sb)
  val @(da, dk) = $B.to_arr(db)
  val @(sfz, sbv) = $A.freeze<byte>(sa)
  val @(dfz, dbv) = $A.freeze<byte>(da)
  val out = (if not(_fits(sk)) then let
      val () = _say("gen-pwa pages: the source path is too long\n")
    in PagesPathTooLong() end
    else (case+ $F.dir_read(sbv, 524288) of
      | ~$R.err(e) => let
          val () = _say_path(sbv, sk)
          val () = _say(": not a readable directory")
          val () = _say_reason(e)
        in PagesSourceRefused() end
      | ~$R.ok(es) => let
          val () = $F.entries_free(es)
        in
          case+ _mkdir(dbv) of
          | ~$R.err(e) => (case+ e of
              | $F.AlreadyExists() => let
                  val () = _say_path(dbv, dk)
                  val () = _say(": the destination exists, nothing was copied\n")
                in PagesDestinationExists() end
              | _ => let
                  val () = _say_path(dbv, dk)
                  val () = _say_reason(e)
                in PagesWriteFailed() end)
          | ~$R.ok(_) => copy_dir(sbv, sk, dbv, dk, PAGES_DEPTH)
        end)): pages_outcome
  val () = $A.drop<byte>(sfz, sbv)
  val () = $A.free<byte>($A.thaw<byte>(sfz))
  val () = $A.drop<byte>(dfz, dbv)
  val () = $A.free<byte>($A.thaw<byte>(dfz))
in out end

fn _with_args {l:agz} (b: !$A.borrow(byte, l, 4096), k: int): pages_outcome = let
  val e0 = _arg_end(b, 0, k)
  val s1 = e0 + 1
  val e1 = _arg_end(b, _nat(s1), k)
  val s2 = e1 + 1
  val e2 = _arg_end(b, _nat(s2), k)
  val s3 = e2 + 1
  val e3 = _arg_end(b, _nat(s3), k)
in
  if k >= 4096 then let
    val () = _say("gen-pwa pages: the arguments are too long\n")
  in PagesUsage() end
  else if s2 >= k || s3 >= k || e3 + 1 < k then let
    val () = _say("usage: gen-pwa pages SOURCE NAME\n")
  in PagesUsage() end
  else if not(_name_ok(b, s3, e3)) then let
    val () = _say("gen-pwa pages: NAME must be one name under dist/pwa: not empty, not . or .., no slash\n")
  in PagesNameRefused() end
  else _run_copy(b, s2, e2, s3, e3)
end

#pub fn pages_wanted (): bool

#pub fn pages_run (): int

implement pages_wanted () = let
  val buf = $A.alloc<byte>(4096)
  val k = _args(buf)
  val @(fz, bv) = $A.freeze<byte>(buf)
  val s = _arg_end(bv, 0, k) + 1
  val e = _arg_end(bv, _nat(s), k)
  val wanted = (e - s = 5 && _at(bv, s) = 112 && _at(bv, s + 1) = 97 && _at(bv, s + 2) = 103
    && _at(bv, s + 3) = 101 && _at(bv, s + 4) = 115 && s < k): bool
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in wanted end

implement pages_run () = let
  val buf = $A.alloc<byte>(4096)
  val k = _args(buf)
  val @(fz, bv) = $A.freeze<byte>(buf)
  val out = _with_args(bv, k)
  val () = $A.drop<byte>(fz, bv)
  val () = $A.free<byte>($A.thaw<byte>(fz))
in
  case+ out of
  | PagesCopied() => 0
  | _ => 1
end
