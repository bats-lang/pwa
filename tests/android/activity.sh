#!/bin/sh
# The activity pwa writes hands each intent's files to the page once
# (bats-lang/quire#247), and the system bars' visibility at each window
# insets dispatch (bats-lang/quire#314). Compiles that MainActivity.java with
# activity/, Capacitor's BridgeActivity and the few Android and androidx
# classes it takes, played, and runs activity/IntentOnce.java and
# activity/SystemBarsReported.java. Needs a JDK.
#
# usage: tests/android/activity.sh <MainActivity.java>
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src/app" "$WORK/classes"
cp -R "$HERE/activity/android" "$HERE/activity/androidx" "$HERE/activity/com" "$HERE/activity/org" "$WORK/src/"
# The app's package is the test's
sed '1s/^package .*;$/package app;/' "$1" > "$WORK/src/app/MainActivity.java"
cp "$HERE/activity/IntentOnce.java" "$HERE/activity/SystemBarsReported.java" "$WORK/src/app/"
javac -nowarn -d "$WORK/classes" $(find "$WORK/src" -name '*.java')
java -cp "$WORK/classes" app.IntentOnce
java -cp "$WORK/classes" app.SystemBarsReported
