(* action_stand_in -- the emulator action of the tests of the smoke test's retry
   (bats-lang/pwa#214; area keyword android-smoke), run in a case's directory with
   PATH starting at the directory of the stand-in sdkmanager: its install group runs
   `sdkmanager --install` as the action does (a failure ends it, before any emulator),
   then the pre-emulator-launch-script's marker is made (the file emulator-installed:
   android.yml's line `touch "$RUNNER_TEMP/emulator-installed"`, which the test checks
   is there), then the test runs: it fails when the file test-fails exists. *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use file as F
#use list as L
#use process as P
#use result as R

staload "smoke_files.sats"

implement main0 () = let
  val () = println! ("##[group]Install Android SDK")
  val installed = run_program("sdkmanager", $L.list_vt_cons(arg_text("--install"),
    $L.list_vt_cons(arg_text("system-images;android-34;default;x86_64"),
    $L.list_vt_cons(arg_text("--channel=0"), $L.list_vt_nil()))), $L.list_vt_nil())
  val () = println! ("##[endgroup]")
in
  if installed <> 0 then let
    val () = prerr! ("##[error]The process '/usr/bin/sh' failed with exit code 1\n")
  in exit_void(1) end
  else let
    val _ = append_x(path2(".", "emulator-installed"))
    val () = println! ("the emulator started; the test runs")
  in
    if size_of(path2(".", "test-fails")) > 0 then let
      val () = println! ("the test failed")
    in exit_void(1) end
    else ()
  end
end
