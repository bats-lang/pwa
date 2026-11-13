#!/bin/sh
# Runs a command and writes, as the last line of its output, how long the
# whole run took, whether the command passed or failed (bats-lang/pwa#319;
# area: job-took):
#
#   job-took.sh <command> [args...]    ->    job took <seconds> s
#
# The seconds count from JOB_TOOK_START (epoch seconds, which e2e-setup's first
# step puts in the job's environment, so the setup is in the number), else
# from this script's own start. The exit status is the command's own.
start=${JOB_TOOK_START:-$(date +%s)}
status=0
"$@" || status=$?
echo "job took $(( $(date +%s) - start )) s"
exit "$status"
