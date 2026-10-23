#!/usr/bin/env bash
# Install the stall capture's native tools (quire#575, #591): gdb for a frozen
# renderer's stacks and core, elfutils (eu-stack, its fallback), libc6-dbg of
# exactly the installed libc6 (names libc's internal functions) and rr (never
# used to record a test: the preflight runs `rr record true` for its verdict).
# keyword: stall-tools (.claude/rules/e2e-setup.md).
#
# Every apt call is bounded twice (pwa#163: `apt-get update` never returned
# for 56 minutes on a stalled mirror, so the attempts after it never ran):
# apt's own -o Acquire::http::Timeout, Acquire::https::Timeout and
# Acquire::Retries (a transfer that stalls fails), and `timeout` around the
# whole call (a hang guard for what apt's options do not reach, never a
# budget: E2E_APT_HANG_S, default 600 s, is far past a slow install). A call
# that fails or is killed makes the next attempt run. A diagnostic for a rare
# freeze never fails the job: whatever cannot be installed is said as a
# warning and the script exits 0 (the capture uses a tool only if it is
# there, and the specs that need one skip, saying why, when it is not).
# E2E_ATTEMPTS (default 3) is the tries of each call, E2E_PAUSE_S (default 5)
# the pause that grows by itself with the attempt.
set -u
attempts=${E2E_ATTEMPTS:-3}
pause=${E2E_PAUSE_S:-5}
hang=${E2E_APT_HANG_S:-600}
net=${E2E_APT_NET_S:-30}
started=$(date +%s)

# apt_bounded <apt-get arguments...>: one bounded call of apt-get
apt_bounded() {
  sudo timeout -k 10 "$hang" apt-get \
    -o "Acquire::http::Timeout=$net" -o "Acquire::https::Timeout=$net" \
    -o Acquire::Retries=3 "$@"
}

# attempt <label> <apt-get arguments...>: up to $attempts bounded calls
attempt() {
  label=$1; shift
  n=1
  while :; do
    apt_bounded "$@"; status=$?
    [ "$status" != 0 ] || return 0
    if [ "$status" = 124 ] || [ "$status" = 137 ]; then
      echo "::warning::$label: apt-get did not return in ${hang}s and was stopped (try $n of $attempts)"
    else
      echo "::warning::$label: apt-get failed with $status (try $n of $attempts)"
    fi
    [ "$n" -lt "$attempts" ] || return 1
    sleep $((pause * n)); n=$((n + 1))
  done
}

installed=no
if attempt "apt-get update" update -q && attempt "gdb, elfutils" install -y -q gdb elfutils; then
  installed=yes
fi
# libc6-dbg of exactly the installed libc6, never an upgrade of libc6 in the middle of a job
libc_version=$(dpkg-query -W -f='${Version}' libc6)
attempt "libc6-dbg" install -y -q --no-upgrade "libc6-dbg=$libc_version" \
  || echo "::warning::libc6-dbg $libc_version is not available: libc's internal functions stay unnamed"
# rr is its own install: a package that is missing must not take gdb with it
attempt "rr" install -y -q rr \
  || echo "::warning::rr is not available: the preflight logs it as not installed"
echo "Install gdb: installed=$installed after $(( $(date +%s) - started )) s"
[ "$installed" = yes ] || echo "::warning::gdb and elfutils are not installed: the stall capture's native stacks are missing"
exit 0
