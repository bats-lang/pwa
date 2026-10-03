#!/bin/sh
# The activity pwa writes hands each intent's files to the page once
# (bats-lang/quire#247). Compiles that MainActivity.java with
# activity/, Capacitor's BridgeActivity and the few Android classes it
# takes, played, and runs activity/IntentOnce.java. Needs a JDK.
#
# usage: tests/android/activity.sh <MainActivity.java>
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src/app" "$WORK/classes"
cp -R "$HERE/activity/android" "$HERE/activity/com" "$HERE/activity/org" "$WORK/src/"
# The app's package is the test's
sed '1s/^package .*;$/package app;/' "$1" > "$WORK/src/app/MainActivity.java"
cp "$HERE/activity/IntentOnce.java" "$WORK/src/app/"
javac -nowarn -d "$WORK/classes" $(find "$WORK/src" -name '*.java')
java -cp "$WORK/classes" app.IntentOnce
