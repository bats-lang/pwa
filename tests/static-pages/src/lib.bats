(* static_pages_test -- the tests of gen-pwa pages (bats-lang/pwa#243; area keyword
   static-pages, .claude/rules/static-pages.md), run by `bats test` in tests/static-pages
   after the example's build-pwa is built (check.yml, the step "gen-pwa pages").

   Each case is a directory build/pages-tests/NAME, made empty with a dist/pwa in it. The
   built binary runs there (`env -C`, so that its dist/pwa is the case's), its exit status
   is read and its standard error is read whole (the first 65536 bytes of up to 4 MiB) and
   searched for the words the outcome must say: the path and the system's reason. The tree
   is compared with `diff -r`, a third-party tool used as it is, since the file package has
   no lstat and no way to make a symbolic link (the avenue for `ln -s`, `mkdir -p`, `rm -rf`
   and `diff -r`: nothing of these is ours to write); the modes are read with the file
   package, and a control makes `diff -r` fail on a tree that differs, so a comparison
   that sees nothing cannot pass. A case that needs a user who cannot write where root can
   (a read-only dist/pwa, a file with no permission) passes without its reason when the
   user is privileged: the copy then succeeds, which the kernel does for root. *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use file as F
#use list as L
#use process as P
#use result as R

(* the built generator, from a case's directory (build/pages-tests/NAME) *)
#define GENERATOR "../../../../../example/dist/debug/build-pwa"

(* ============================================================
   Text, paths and arguments
   ============================================================ *)

fn _arg_of (text: $B.builder_v): $P.arg_entry = let
  val @(array, size) = $B.into_arr(text)
in @(array, size) end

fn _arg {n:nat | n < 4000} (text: string n): $P.arg_entry = let
  var out : $B.builder(0) = $B.create()
  val () = $B.bput(out, text)
in _arg_of(out) end

fn _nil (): $L.listv($P.arg_entry) = $L.list_vt_nil()

fn _cons (first: $P.arg_entry, rest: $L.listv($P.arg_entry)): $L.listv($P.arg_entry) =
  $L.list_vt_cons(first, rest)

(* build/pages-tests/NAME/REL as a builder (REL may be empty) *)
fn _path {c,r:nat | c < 100; r < 400} (name: string c, rel: string r): $B.builder_v = let
  var out : $B.builder(0) = $B.create()
  val () = $B.bput(out, "build/pages-tests/")
  val () = $B.bput(out, name)
  val () = $B.bput(out, "/")
  val () = $B.bput(out, rel)
in out end

(* the path as an array of 524288 bytes, the text then zeros *)
fn _zero_path (path: $B.builder_v): [l:agz] $A.arr(byte, l, 524288) = let
  var held : $B.builder_v = path
  val @(array, _) = $B.to_arr(held)
in array end

(* ============================================================
   Running programs
   ============================================================ *)

(* the program (found on PATH) with the arguments, the streams shared: its exit status,
   ~1 when it could not be run *)
fn _run {p:nat | p < 4000} (program: string p, args: $L.listv($P.arg_entry)): int = let
  val @(nul | path) = $P.path_of_string_proved(program)
  val @(frozen, view) = $A.barr_freeze(path)
  val argv = _cons(_arg(program), args)
  val spawned = $P.spawn_inherit_env_with_proved(nul | view, argv, _nil(), $P.inherit(), $P.inherit(), $P.inherit())
  val () = $A.cborrow_drop(frozen, view)
  val () = $A.barr_free($A.barr_thaw(frozen))
in
  case+ spawned of
  | ~$R.ok(spawned_process) => let
      val+ ~$P.spawn_pipes_mk(child, stdin_pipe, stdout_pipe, stderr_pipe) = spawned_process
      val () = $P.pipe_end_close(stdin_pipe)
      val () = $P.pipe_end_close(stdout_pipe)
      val () = $P.pipe_end_close(stderr_pipe)
    in (case+ $P.child_wait(child) of | ~$R.ok(code) => code | ~$R.err(_) => ~1) end
  | ~$R.err(_) => ~1
end

(* src[j, k) to dst at at + j *)
fun _move {l,ls:agz}{k:nat | k <= 4096}{at:nat | at + k <= 65536}{j:nat | j <= k} .<k - j>.
  (source: !$A.arr(byte, ls, 4096), destination: !$A.arr(byte, l, 65536), j: int j, k: int k, at: int at): void =
  if j >= k then ()
  else let
    val () = $A.set<byte>(destination, at + j, $A.get<byte>(source, j))
  in _move(source, destination, j + 1, k, at) end

(* The bytes of fd to its end into acc from place at: the place after them. Reads at most
   f chunks of 4096 bytes; the bytes past the 65536th are read and dropped, so the child
   never blocks on a full pipe. *)
fun _drain {l,ls:agz}{at:nat | at <= 65536}{f:nat} .<f>.
  (fd: !$F.fd, acc: !$A.arr(byte, l, 65536), scratch: !$A.arr(byte, ls, 4096), at: int at, f: int f)
  : [c:nat | c <= 65536] int c =
  if f <= 0 then at
  else (case+ $F.file_read(fd, scratch, 4096) of
    | ~$R.err(_) => at
    | ~$R.ok(k) =>
        if k <= 0 then at
        else if at + k <= 65536 then let
          val () = _move(scratch, acc, 0, k, at)
        in _drain(fd, acc, scratch, at + k, f - 1) end
        else _drain(fd, acc, scratch, at, f - 1))

(* Whether view[at + j ..] starts with the literal from its place j *)
fun _match_at {l:agz}{cap:pos}{n:nat | n <= cap}{at:nat}{m:nat}{j:nat | j <= m} .<m - j>.
  (view: !$A.borrow(byte, l, cap), n: int n, at: int at, literal: string m, m: int m, j: int j): bool =
  if j >= m then true
  else if at + j >= n then false
  else if byte2int0($A.read<byte>(view, at + j)) <> char2int0(string_get_at(literal, j)) then false
  else _match_at(view, n, at, literal, m, j + 1)

fun _contains_from {l:agz}{cap:pos}{n:nat | n <= cap}{at:nat | at <= n}{m:nat} .<n - at>.
  (view: !$A.borrow(byte, l, cap), n: int n, at: int at, literal: string m, m: int m): bool =
  if at >= n then false
  else if _match_at(view, n, at, literal, m, 0) then true
  else _contains_from(view, n, at + 1, literal, m)

(* Whether view[0, n) holds the literal (the empty literal is always held) *)
fn _contains {l:agz}{cap:pos}{n:nat | n <= cap}{m:nat}
  (view: !$A.borrow(byte, l, cap), n: int n, literal: string m): bool = let
  val m = g1u2i(string1_length(literal))
in if m = 0 then true else _contains_from(view, n, 0, literal, m) end

(* The generator in the case's directory with these arguments after `pages`: its exit
   status, and whether its standard error holds both words *)
fn _pages {c:nat | c < 100}{a,b:nat}
  (name: string c, args: $L.listv($P.arg_entry), first: string a, second: string b): @(int, bool) = let
  val @(nul | path) = $P.path_of_string_proved("env")
  val @(frozen, view) = $A.barr_freeze(path)
  val argv = _cons(_arg("env"), _cons(_arg("-C"), _cons(_arg_of(_path(name, "")),
    _cons(_arg(GENERATOR), _cons(_arg("pages"), args)))))
  val spawned = $P.spawn_inherit_env_with_proved(nul | view, argv, _nil(), $P.inherit(), $P.inherit(), $P.pipe_new())
  val () = $A.cborrow_drop(frozen, view)
  val () = $A.barr_free($A.barr_thaw(frozen))
in
  case+ spawned of
  | ~$R.ok(spawned_process) => let
      val+ ~$P.spawn_pipes_mk(child, stdin_pipe, stdout_pipe, stderr_pipe) = spawned_process
      val () = $P.pipe_end_close(stdin_pipe)
      val () = $P.pipe_end_close(stdout_pipe)
      val+ ~$P.pipe_fd(stderr_fd) = stderr_pipe
      val acc = $A.alloc<byte>(65536)
      val scratch = $A.alloc<byte>(4096)
      val count = _drain(stderr_fd, acc, scratch, 0, 1024)
      val () = $A.free<byte>(scratch)
      val () = $R.discard<int><$F.io_error>($F.file_close(stderr_fd))
      val code = (case+ $P.child_wait(child) of | ~$R.ok(c) => c | ~$R.err(_) => ~1): int
      val @(acc_frozen, acc_view) = $A.freeze<byte>(acc)
      val said = (_contains(acc_view, count, first) && _contains(acc_view, count, second)): bool
      val () = $A.drop<byte>(acc_frozen, acc_view)
      val () = $A.free<byte>($A.thaw<byte>(acc_frozen))
    in @(code, said) end
  | ~$R.err(_) => @(~1, false)
end

(* ============================================================
   Files
   ============================================================ *)

(* The file at the path opened as asked; a file it makes has the mode *)
fn _open (path: $B.builder_v, access: $F.access, opening: $F.opening, mode: int): $R.result($F.fd, $F.io_error) = let
  val array = _zero_path(path)
  val @(frozen, view) = $A.freeze<byte>(array)
  val opened = $F.file_open(view, 524288, access, opening, mode)
  val () = $A.drop<byte>(frozen, view)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in opened end

(* The file made (or emptied) to hold exactly the text, with the mode *)
fn _make_text {sn:nat | sn < 4096} (path: $B.builder_v, mode: int, text: string sn): bool =
  case+ _open(path, $F.WriteOnly(), $F.CreateOrTruncate(), mode) of
  | ~$R.err(_) => false
  | ~$R.ok(fd) => let
      val n = g1u2i(string1_length(text))
      val written = (if n > 0 then let
          val bytes = $A.alloc<byte>(n)
          fun fill {l:agz}{sn:pos}{i:nat | i <= sn} .<sn - i>.
            (a: !$A.arr(byte, l, sn), s: string sn, n: int sn, i: int i): void =
            if i >= n then ()
            else let
              val () = $A.set<byte>(a, i, int2byte0(char2int0(string_get_at(s, i))))
            in fill(a, s, n, i + 1) end
          val () = fill(bytes, text, n, 0)
          val @(frozen, view) = $A.freeze<byte>(bytes)
          val result = (case+ $F.file_write(fd, view, n) of | ~$R.ok(_) => true | ~$R.err(_) => false): bool
          val () = $A.drop<byte>(frozen, view)
          val () = $A.free<byte>($A.thaw<byte>(frozen))
        in result end
        else true): bool
      val closed = (case+ $F.file_close(fd) of | ~$R.ok(_) => true | ~$R.err(_) => false): bool
    in written && closed end

(* A file of bytes no text holds: 0, 1, 255, then "bin" *)
fn _make_binary (path: $B.builder_v): bool =
  case+ _open(path, $F.WriteOnly(), $F.CreateOrTruncate(), 420) of
  | ~$R.err(_) => false
  | ~$R.ok(fd) => let
      val bytes = $A.alloc<byte>(6)
      val () = $A.set<byte>(bytes, 0, int2byte0(0))
      val () = $A.set<byte>(bytes, 1, int2byte0(1))
      val () = $A.set<byte>(bytes, 2, int2byte0(255))
      val () = $A.set<byte>(bytes, 3, int2byte0(98))
      val () = $A.set<byte>(bytes, 4, int2byte0(105))
      val () = $A.set<byte>(bytes, 5, int2byte0(110))
      val @(frozen, view) = $A.freeze<byte>(bytes)
      val written = (case+ $F.file_write(fd, view, 6) of | ~$R.ok(_) => true | ~$R.err(_) => false): bool
      val () = $A.drop<byte>(frozen, view)
      val () = $A.free<byte>($A.thaw<byte>(frozen))
      val closed = (case+ $F.file_close(fd) of | ~$R.ok(_) => true | ~$R.err(_) => false): bool
    in written && closed end

(* Whether the file holds exactly the text (at most 4096 bytes) *)
fn _holds {sn:nat | sn < 4096} (path: $B.builder_v, text: string sn): bool =
  case+ _open(path, $F.ReadOnly(), $F.OpenExisting(), 0) of
  | ~$R.err(_) => false
  | ~$R.ok(fd) => let
      val buffer = $A.alloc<byte>(4096)
      val count = (case+ $F.file_read(fd, buffer, 4096) of | ~$R.ok(k) => k | ~$R.err(_) => ~1): int
      val () = $R.discard<int><$F.io_error>($F.file_close(fd))
      val @(frozen, view) = $A.freeze<byte>(buffer)
      val expected = g1u2i(string1_length(text))
      val same = (if count = expected && count >= 0 && count <= 4096 then _match_at(view, 4096, 0, text, expected, 0) else false): bool
      val () = $A.drop<byte>(frozen, view)
      val () = $A.free<byte>($A.thaw<byte>(frozen))
    in same end

fn _exists (path: $B.builder_v): bool = let
  val array = _zero_path(path)
  val @(frozen, view) = $A.freeze<byte>(array)
  val there = $F.file_exists(view, 524288)
  val () = $A.drop<byte>(frozen, view)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in there end

(* The permission bits of the file, ~1 when they cannot be read *)
fn _mode_of (path: $B.builder_v): int = let
  val array = _zero_path(path)
  val @(frozen, view) = $A.freeze<byte>(array)
  val mode = (case+ $F.file_mode(view, 524288) of | ~$R.ok(m) => m | ~$R.err(_) => ~1): int
  val () = $A.drop<byte>(frozen, view)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in mode end

fn _chmod (path: $B.builder_v, mode: int): bool = let
  val array = _zero_path(path)
  val @(frozen, view) = $A.freeze<byte>(array)
  val done = (case+ $F.file_chmod(view, 524288, mode) of | ~$R.ok(_) => true | ~$R.err(_) => false): bool
  val () = $A.drop<byte>(frozen, view)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in done end

(* ============================================================
   Cases
   ============================================================ *)

(* An empty case with a dist/pwa in it *)
fn _fresh {c:nat | c < 100} (name: string c): bool = let
  val removed = _run("rm", _cons(_arg("-rf"), _cons(_arg("--"), _cons(_arg_of(_path(name, "")), _nil()))))
  val made = _run("mkdir", _cons(_arg("-p"), _cons(_arg("--"), _cons(_arg_of(_path(name, "dist/pwa")), _nil()))))
in removed = 0 && made = 0 end

fn _mkdir_p {c,r:nat | c < 100; r < 400} (name: string c, rel: string r): bool =
  _run("mkdir", _cons(_arg("-p"), _cons(_arg("--"), _cons(_arg_of(_path(name, rel)), _nil())))) = 0

fn _link {c,r,t:nat | c < 100; r < 400; t < 400} (name: string c, target: string t, rel: string r): bool =
  _run("ln", _cons(_arg("-s"), _cons(_arg("--"), _cons(_arg(target), _cons(_arg_of(_path(name, rel)), _nil()))))) = 0

fn _remove {c,r:nat | c < 100; r < 400} (name: string c, rel: string r): bool =
  _run("rm", _cons(_arg("-rf"), _cons(_arg("--"), _cons(_arg_of(_path(name, rel)), _nil())))) = 0

(* diff -r of two trees of the case: its exit status, 0 only when they are the same *)
fn _diff {c,a,b:nat | c < 100; a < 400; b < 400} (name: string c, left: string a, right: string b): int =
  _run("diff", _cons(_arg("-r"), _cons(_arg("--"), _cons(_arg_of(_path(name, left)), _cons(_arg_of(_path(name, right)), _nil())))))

(* The source tree of the copy cases: text, a binary file, a nested directory, a file
   with the executable bits, an empty file and an empty directory *)
fn _source {c:nat | c < 100} (name: string c, root: string 3): bool =
  _mkdir_p(name, "src/a/b") && _mkdir_p(name, "src/empty")
  && _make_text(_path(name, "src/index.html"), 420, "index\n")
  && _make_binary(_path(name, "src/a/b/blob.bin"))
  && _make_text(_path(name, "src/a/run.sh"), 493, "#!/bin/sh\n")
  && _make_text(_path(name, "src/zero"), 420, "")

(* ============================================================
   Tests (bats test)
   ============================================================ *)

$UNITTEST.run begin

(* the tree is copied, files byte for byte, the mode kept, an empty directory kept *)
fn test_copy_tree (): bool = let
  val ready = _fresh("copy") && _source("copy", "src")
  val @(status, _) = _pages("copy", _cons(_arg("src"), _cons(_arg("home"), _nil())), "", "")
in
  ready && status = 0 && _diff("copy", "src", "dist/pwa/home") = 0
  && _mode_of(_path("copy", "dist/pwa/home/a/run.sh")) = 493
  && _mode_of(_path("copy", "dist/pwa/home/index.html")) = 420
  && _exists(_path("copy", "dist/pwa/home/empty"))
end

(* the control of the comparison: it fails on a changed file, a missing file and a missing directory *)
fn test_comparison_sees_a_difference (): bool = let
  val ready = _fresh("control") && _source("control", "src")
  val @(status, _) = _pages("control", _cons(_arg("src"), _cons(_arg("home"), _nil())), "", "")
  val same = _diff("control", "src", "dist/pwa/home")
  val changed = _make_text(_path("control", "dist/pwa/home/index.html"), 420, "changed\n")
  val changed_diff = _diff("control", "src", "dist/pwa/home")
  val restored = _make_text(_path("control", "dist/pwa/home/index.html"), 420, "index\n")
  val no_file = _remove("control", "dist/pwa/home/zero")
  val no_file_diff = _diff("control", "src", "dist/pwa/home")
  val no_directory = _remove("control", "dist/pwa/home/a")
  val no_directory_diff = _diff("control", "src", "dist/pwa/home")
in
  ready && status = 0 && same = 0 && changed && changed_diff = 1 && restored && no_file
  && no_file_diff = 1 && no_directory && no_directory_diff = 1
end

(* a destination that exists is refused, said, and left as it was *)
fn test_destination_exists (): bool = let
  val ready = _fresh("exists") && _source("exists", "src") && _mkdir_p("exists", "dist/pwa/home")
    && _make_text(_path("exists", "dist/pwa/home/index.html"), 420, "keep\n")
  val @(status, said) = _pages("exists", _cons(_arg("src"), _cons(_arg("home"), _nil())),
    "dist/pwa/home: the destination exists", "nothing was copied")
in
  ready && status = 1 && said && _holds(_path("exists", "dist/pwa/home/index.html"), "keep\n")
  && ~_exists(_path("exists", "dist/pwa/home/a"))
end

(* a source that is missing, or is a file, is refused before anything is made *)
fn test_source_missing (): bool = let
  val ready = _fresh("missing")
  val @(status, said) = _pages("missing", _cons(_arg("nowhere"), _cons(_arg("other"), _nil())),
    "nowhere: not a readable directory", "not found")
in ready && status = 1 && said && ~_exists(_path("missing", "dist/pwa/other")) end

fn test_source_is_a_file (): bool = let
  val ready = _fresh("file-source") && _make_text(_path("file-source", "page.html"), 420, "x\n")
  val @(status, said) = _pages("file-source", _cons(_arg("page.html"), _cons(_arg("other"), _nil())),
    "page.html: not a readable directory", "not a directory")
in ready && status = 1 && said && ~_exists(_path("file-source", "dist/pwa/other")) end

(* a name that leaves dist/pwa, or is not a name, is refused and said, and nothing is made *)
fn _name_refused {n:nat | n < 400} (name: string n): bool = let
  val ready = _fresh("names") && _mkdir_p("names", "src")
  val @(status, said) = _pages("names", _cons(_arg("src"), _cons(_arg(name), _nil())), "NAME must be one name", "no slash")
in ready && status = 1 && said && ~_exists(_path("names", "dist/x")) && ~_exists(_path("names", "dist/pwa/x")) end

fn test_name_empty (): bool = _name_refused("")
fn test_name_dot (): bool = _name_refused(".")
fn test_name_dotdot (): bool = _name_refused("..")
fn test_name_up_and_out (): bool = _name_refused("../x")
fn test_name_with_a_slash (): bool = _name_refused("a/b")
fn test_name_absolute (): bool = _name_refused("/abs")

(* the arguments are exactly SOURCE and NAME *)
fn test_usage_no_arguments (): bool = let
  val ready = _fresh("usage0")
  val @(status, said) = _pages("usage0", _nil(), "usage: gen-pwa pages SOURCE NAME", "")
in ready && status = 1 && said end

fn test_usage_one_argument (): bool = let
  val ready = _fresh("usage1")
  val @(status, said) = _pages("usage1", _cons(_arg("src"), _nil()), "usage: gen-pwa pages SOURCE NAME", "")
in ready && status = 1 && said end

fn test_usage_three_arguments (): bool = let
  val ready = _fresh("usage3") && _mkdir_p("usage3", "src")
  val @(status, said) = _pages("usage3", _cons(_arg("src"), _cons(_arg("a"), _cons(_arg("b"), _nil()))),
    "usage: gen-pwa pages SOURCE NAME", "")
in ready && status = 1 && said && ~_exists(_path("usage3", "dist/pwa/a")) end

(* a write that fails: dist/pwa that cannot be written (a privileged user can write it, and
   the copy then succeeds), and dist/pwa that is not there *)
fn test_write_fails_read_only (): bool = let
  val ready = _fresh("read-only") && _source("read-only", "src") && _chmod(_path("read-only", "dist/pwa"), 365)
  val @(status, said) = _pages("read-only", _cons(_arg("src"), _cons(_arg("home"), _nil())),
    "dist/pwa/home: ", "permission denied")
  val restored = _chmod(_path("read-only", "dist/pwa"), 493)
in ready && restored && (if status = 0 then _exists(_path("read-only", "dist/pwa/home/index.html")) else status = 1 && said) end

fn test_write_fails_no_dist (): bool = let
  val ready = _fresh("no-dist") && _source("no-dist", "src") && _remove("no-dist", "dist")
  val @(status, said) = _pages("no-dist", _cons(_arg("src"), _cons(_arg("home"), _nil())),
    "dist/pwa/home: ", "not found")
in ready && status = 1 && said end

(* a read that fails: a link to nothing, a link that loops, a file nobody may read *)
fn test_read_fails_dangling_link (): bool = let
  val ready = _fresh("dangling") && _mkdir_p("dangling", "src") && _link("dangling", "nowhere", "src/gone")
  val @(status, said) = _pages("dangling", _cons(_arg("src"), _cons(_arg("home"), _nil())),
    "src/gone: ", "not found")
in ready && status = 1 && said end

fn test_read_fails_looping_link (): bool = let
  val ready = _fresh("loop") && _mkdir_p("loop", "src") && _link("loop", ".", "src/self")
  val @(status, said) = _pages("loop", _cons(_arg("src"), _cons(_arg("home"), _nil())),
    "src/self/self/self", "too many levels of symbolic links")
in ready && status = 1 && said end

fn test_read_fails_unreadable_file (): bool = let
  val ready = _fresh("unreadable") && _mkdir_p("unreadable", "src")
    && _make_text(_path("unreadable", "src/secret"), 420, "x") && _chmod(_path("unreadable", "src/secret"), 0)
  val @(status, said) = _pages("unreadable", _cons(_arg("src"), _cons(_arg("home"), _nil())),
    "src/secret: ", "permission denied")
  val restored = _chmod(_path("unreadable", "src/secret"), 420)
in ready && restored && (if status = 0 then _holds(_path("unreadable", "dist/pwa/home/secret"), "x") else status = 1 && said) end

(* a tree deeper than 64 levels is refused by the depth limit *)
fun _levels {n:nat}{j:nat | n + 2 * j <= 524288} .<j>.
  (out: !$B.builder(n) >> $B.builder(n + 2 * j), j: int j): void =
  if j <= 0 then ()
  else let
    val () = $B.bput(out, "/d")
  in _levels(out, j - 1) end

fn test_too_deep (): bool = let
  val ready = _fresh("deep")
  var deep : $B.builder(0) = $B.create()
  val () = $B.bput(deep, "build/pages-tests/deep/src")
  val () = _levels(deep, 66)
  val made = _run("mkdir", _cons(_arg("-p"), _cons(_arg("--"), _cons(_arg_of(deep), _nil()))))
  val @(status, said) = _pages("deep", _cons(_arg("src"), _cons(_arg("home"), _nil())),
    "more than 64 levels of directories", "")
in ready && made = 0 && status = 1 && said end

end
