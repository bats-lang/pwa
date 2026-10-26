(* smoke_tests -- the tests of the smoke test's retry (bats-lang/pwa#214; area keyword
   android-smoke, .claude/rules/android-smoke.md), run by `bats test` in
   tools/android-sdk-pins after `bats build`, as tools/pin-audit's tests are (they run
   its built binary against stand-ins in a directory of each case under build/).

   What decides is the built android-sdk-pins `decide` (the decision, tested on every
   input below) and android.yml's wiring, checked as exact text: attempt 1 with
   continue-on-error and the anchors of its env and with, the pre-emulator-launch-script's
   marker, the step "Whether the emulator step runs again" with the outcome of attempt 1
   in its env, and attempt 2 with the one condition `steps.decide.outputs.again == 'true'`
   and the aliases, in this order. A case then plays the steps in that order with a
   stand-in sdkmanager (it serves a cut-short manifest on its first call, then the whole
   one) and a stand-in action (the install, the marker, the test): the stand-ins and the
   tool are built binaries, copied to the case's directory and run there with `env -C`.
   A change of android.yml's wiring or condition fails the check, so no case runs. *)

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
   android.yml's wiring, as exact text in this order
   ============================================================ *)

fn _next {l:agz}{size:nat | size <= 131072}{from:int | from <= size}{literal_size:nat}
  (view: !$A.borrow(byte, l, 131072), size: int size, from: int from, literal: string literal_size)
  : [place:int | ~1 <= place; place <= size] int place =
  if from < 0 then ~1 else find_from(view, size, from, literal)

(* Whether the file at the path (consumed) holds the wiring, in order: attempt 1 (continue-on-error, anchors),
   the marker, the decision step, attempt 2 with its one condition and the aliases, the log step's outcome *)
fn _wired (path: $B.builder_v): bool = let
  val buffer = $A.alloc<byte>(131072)
  val count = read_into(path, buffer)
  val @(frozen, view) = $A.freeze<byte>(buffer)
  val ok = (if count < 0 then false else let
      val attempt_1 = _next(view, count, 0, "      - name: Run the app on an emulator (attempt 1 of 2)\n        id: emulator1\n        continue-on-error: true\n        uses: reactivecircus/android-emulator-runner@")
      val env_anchor = _next(view, count, attempt_1, "        env: &emulator-env\n")
      val with_anchor = _next(view, count, env_anchor, "        with: &emulator-with\n")
      val marker = _next(view, count, with_anchor, "          pre-emulator-launch-script: |\n            touch \"$RUNNER_TEMP/emulator-installed\"\n")
      val decision = _next(view, count, marker, "      - name: Whether the emulator step runs again\n        id: decide\n        env:\n          ANDROID_SMOKE_OUTCOME: ${{ steps.emulator1.outcome }}\n          ANDROID_SMOKE_ATTEMPT: '1'\n          ANDROID_SMOKE_ATTEMPTS: '2'\n        run: |\n          \"$GITHUB_WORKSPACE/sdk-pins-bin/android-sdk-pins\" decide \"$RUNNER_TEMP/emulator-installed\" >> \"$GITHUB_OUTPUT\"\n")
      val attempt_2 = _next(view, count, decision, "      - name: Run the app on an emulator (attempt 2 of 2)\n        id: emulator2\n        if: ${{ steps.decide.outputs.again == 'true' }}\n        uses: reactivecircus/android-emulator-runner@")
      val aliases = _next(view, count, attempt_2, "        env: *emulator-env\n        with: *emulator-with\n")
      val outcome = _next(view, count, aliases, "OUTCOME: ${{ steps.emulator2.outcome != 'skipped' && steps.emulator2.outcome || steps.emulator1.outcome }}")
    in attempt_1 >= 0 && env_anchor >= 0 && with_anchor >= 0 && marker >= 0 && decision >= 0
       && attempt_2 >= 0 && aliases >= 0 && outcome >= 0 end): bool
  val () = $A.drop<byte>(frozen, view)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in ok end

(* bytes[start, stop) of view appended to out *)
fun _copy_range {l:agz}{size:nat | size <= 131072}{start:nat}{stop:int | start <= stop; stop <= size} .<stop - start>.
  (view: !$A.borrow(byte, l, 131072), start: int start, stop: int stop, size: int size,
   out: !$B.builder_v >> $B.builder_v): void =
  if start >= stop then ()
  else if $B.length(out) >= 524288 then ()
  else let
    val () = $B.put_char(out, $AR.low_byte(byte2int0($A.read<byte>(view, start))))
  in _copy_range(view, start + 1, stop, size, out) end

(* The file at yml with attempt 2's condition changed (`'true'` to `'maybe'`), written to the
   case's android.yml: whether it was made *)
fn _injected {n:nat | n < 100} (name: string n, yml: $B.builder_v): bool = let
  val buffer = $A.alloc<byte>(131072)
  val count = read_into(yml, buffer)
  val @(frozen, view) = $A.freeze<byte>(buffer)
  val condition = "        if: ${{ steps.decide.outputs.again == "
  val made = (if count < 0 then false else let
      val at = find_from(view, count, 0, condition)
    in
      if at < 0 then false
      else let
        val after = at + 46 + 6
        var out : $B.builder_v = $B.create()
        val () = (if after <= count then let
            val () = _copy_range(view, 0, at + 46, count, out)
            val () = (if $B.length(out) < 524000 then $B.bput(out, "'maybe'") else ())
          in _copy_range(view, after, count, count, out) end
          else ())
      in write_text(_case_path(name, "android.yml"), out) end
    end): bool
  val () = $A.drop<byte>(frozen, view)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in made end

(* ============================================================
   The flow of android.yml's steps
   ============================================================ *)

(* The steps in android.yml's order, when its wiring is the checked one (else 99): attempt 1, the
   decision with attempt 1's outcome, attempt 2 when the decision printed again=true. The status
   of the job: the decision's when it failed, else the last attempt's *)
fn _flow {n:nat | n < 100} (name: string n, yml: $B.builder_v): int =
  if ~_wired(yml) then 99
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
  val status = _flow("cut-then-whole", text_of("../../.github/workflows/android.yml"))
in status = 0 && size_of(_case_path("cut-then-whole", "calls")) = 2 end

(* the same fixture against android.yml with attempt 2's condition changed: the
   wiring check fails and nothing runs (the injection) *)
fn test_condition_changed_fails (): bool = let
  val () = _fresh("condition-changed", 1, false)
  val made = _injected("condition-changed", text_of("../../.github/workflows/android.yml"))
  val status = _flow("condition-changed", _case_path("condition-changed", "android.yml"))
in made && status = 99 && size_of(_case_path("condition-changed", "calls")) = 0 end

(* a failure of the test after the emulator started is the job's failure and not run again *)
fn test_test_failure_not_run_again (): bool = let
  val () = _fresh("test-fails", 0, true)
  val status = _flow("test-fails", text_of("../../.github/workflows/android.yml"))
in status = 1 && size_of(_case_path("test-fails", "calls")) = 1 end

(* the install fails on both attempts: two attempts, a failure *)
fn test_always_cut_fails (): bool = let
  val () = _fresh("always-cut", 2, false)
  val status = _flow("always-cut", text_of("../../.github/workflows/android.yml"))
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
