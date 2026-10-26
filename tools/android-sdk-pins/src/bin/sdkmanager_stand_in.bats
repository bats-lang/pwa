(* sdkmanager_stand_in -- the sdkmanager of the tests of the smoke test's retry
   (bats-lang/pwa#214; area keyword android-smoke): a copy of it named sdkmanager
   is put in a directory on PATH and run in a case's directory. Each call adds a
   byte to the file calls; while the number of calls is at most the size of the
   file cut (the number of manifests that come cut short), it says what the real
   one said on the cut-short Google TV manifest and exits 1, else it succeeds. *)

#include "share/atspre_staload.hats"

#use array as A
#use builder as B
#use file as F
#use list as L
#use process as P
#use result as R

staload "smoke_files.sats"

implement main0 () = let
  val _ = append_x(path2(".", "calls"))
  val calls = size_of(path2(".", "calls"))
  val cut = size_of(path2(".", "cut"))
in
  if calls <= cut then let
    val () = prerr! ("Warning: https://dl.google.com/android/repository/sys-img/google-tv/sys-img2-3.xml parsing problem. XML document structures must start and end within the same entity.\n")
    val () = prerr! ("Warning: Failed to find package 'system-images;android-34;default;x86_64'\n")
  in exit_void(1) end
  else println! ("Installing the packages (the action sends this to /dev/null)")
end
