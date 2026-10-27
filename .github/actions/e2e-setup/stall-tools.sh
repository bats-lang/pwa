#!/usr/bin/env bash
#   stall-tools.sh key      updates apt's index, resolves the packages, and writes
#                           `key=<cache key>` (names their versions) to $GITHUB_OUTPUT
#   stall-tools.sh install  installs them, the .debs coming from $STALL_DEBS_DIR
#                           (what actions/cache restored) when they are there
# Install the stall capture's native tools (quire#575, #591): gdb for a frozen
# renderer's stacks and core, elfutils (eu-stack, its fallback), libc6-dbg of
# exactly the installed libc6 (names libc's internal functions) and rr (never
# used to record a test: the preflight runs `rr record true` for its verdict).
# keyword: stall-tools (.claude/rules/e2e-setup.md).
#
# Every apt call is bounded twice (pwa#163: a call that never returns would
# stop the attempts after it):
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
#
# The packages are kept between runs (pwa#227: 15 MB a job from a mirror some
# runners reach at 55 kB/s, 631 s in one job): `apt-get -s install` names what
# would be installed (the Inst lines, with versions) and the key is a hash of
# those names, versions and architectures and the installed libc6's version. A
# restored .deb is copied to apt's archives and `apt-get install --download-only`
# then asks the mirror only for what is not there: apt itself checks an archive
# against the index's size and hashes, so a stale or damaged .deb is fetched again and
# never installed, whatever key found it. A package the cache lacks comes from the
# mirror as before, bounded as before. The cache is rewritten only when every
# resolved package was fetched (a partial cache would stay under its key).
set -u
attempts=${E2E_ATTEMPTS:-3}
pause=${E2E_PAUSE_S:-5}
hang=${E2E_APT_HANG_S:-600}
net=${E2E_APT_NET_S:-30}
started=$(date +%s)
state=${E2E_STALL_STATE:-${RUNNER_TEMP:-/tmp}/stall-tools-state}
archives=${E2E_APT_ARCHIVES:-/var/cache/apt/archives}

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


# deb_names <apt-get -s install output>: name_version_arch.deb of each Inst line
# (apt writes an epoch's colon as %3a in the file name)
deb_names() {
  while IFS= read -r line; do
    if [[ $line =~ ^Inst[[:space:]]+([^[:space:]]+)[[:space:]]+(\[[^]]*\][[:space:]]+)?\(([^[:space:]]+)[[:space:]][^[]*\[([^]]+)\]\) ]]; then
      echo "${BASH_REMATCH[1]}_${BASH_REMATCH[3]//:/%3a}_${BASH_REMATCH[4]}.deb"
    fi
  done
}

libc_version=$(dpkg-query -W -f='${Version}' libc6)

# prepare: the index updated once and the packages resolved into $state/expected;
# libc6-dbg of exactly the installed libc6, never an upgrade of libc6 in the middle of a job
prepare() {
  [ ! -f "$state/prepared" ] || return 0
  rm -rf "$state"; mkdir -p "$state"
  attempt "apt-get update" update -q || return 1
  {
    apt_bounded -s install -y -q gdb elfutils 2>/dev/null | deb_names
    apt_bounded -s install -y -q --no-upgrade "libc6-dbg=$libc_version" 2>/dev/null | deb_names
    apt_bounded -s install -y -q rr 2>/dev/null | deb_names
  } | sort -u > "$state/expected"
  : > "$state/prepared"
}

# fetched <label> <apt-get install arguments...>: the .debs into apt's archives (a hit
# finds them there and asks the mirror for nothing), up to $attempts bounded calls
fetched() { label=$1; shift; attempt "$label" install -y -q --download-only "$@"; }

case ${1:-} in
  key)
    : "${GITHUB_OUTPUT:?the step output file}"
    if prepare; then
      names=$(wc -l < "$state/expected" | tr -d ' ')
      sum=$(sha256sum < "$state/expected" | cut -c1-16)
      echo "key=stall-tools-${RUNNER_OS:-linux}-${RUNNER_ARCH:-x64}-libc6-$libc_version-$names-$sum" >> "$GITHUB_OUTPUT"
    else
      # nothing to name: a key no later run looks for, so nothing is restored and a miss is saved harmlessly
      echo "key=stall-tools-unresolved-${GITHUB_RUN_ID:-0}-${GITHUB_RUN_ATTEMPT:-0}-${GITHUB_JOB:-job}" >> "$GITHUB_OUTPUT"
    fi
    exit 0
    ;;
  install) ;;
  *)
    echo "usage: stall-tools.sh key|install" >&2
    exit 2
    ;;
esac

debs=${STALL_DEBS_DIR:?the directory of the cached .debs}
installed=no
if prepare; then
  total=0; cached=0
  while IFS= read -r deb; do
    total=$((total + 1))
    if [ -f "$debs/$deb" ]; then cached=$((cached + 1)); sudo cp -f "$debs/$deb" "$archives/$deb"; fi
  done < "$state/expected"
  echo "Stall tools: $cached of $total packages restored from the cache"
  fetch_gdb=no; fetch_libc=no; fetch_rr=no
  fetched "gdb, elfutils" gdb elfutils && fetch_gdb=yes
  fetched "libc6-dbg" --no-upgrade "libc6-dbg=$libc_version" && fetch_libc=yes
  fetched "rr" rr && fetch_rr=yes
  # the cache holds exactly the resolved packages, or nothing
  if [ "$cached" != "$total" ] && [ "$fetch_gdb$fetch_libc$fetch_rr" = yesyesyes ]; then
    rm -rf "$debs"; mkdir -p "$debs"
    while IFS= read -r deb; do cp -f "$archives/$deb" "$debs/$deb" || { rm -rf "$debs"; break; }; done < "$state/expected"
  fi
  if [ "$fetch_gdb" = yes ] && attempt "gdb, elfutils" install -y -q gdb elfutils; then
    installed=yes
  fi
  if [ "$fetch_libc" = yes ]; then
    attempt "libc6-dbg" install -y -q --no-upgrade "libc6-dbg=$libc_version" \
      || echo "::warning::libc6-dbg $libc_version is not available: libc's internal functions stay unnamed"
  else
    echo "::warning::libc6-dbg $libc_version is not available: libc's internal functions stay unnamed"
  fi
  # rr is its own install: a package that is missing must not take gdb with it
  if [ "$fetch_rr" = yes ]; then
    attempt "rr" install -y -q rr || echo "::warning::rr is not available: the preflight logs it as not installed"
  else
    echo "::warning::rr is not available: the preflight logs it as not installed"
  fi
fi
echo "Install gdb: installed=$installed after $(( $(date +%s) - started )) s"
[ "$installed" = yes ] || echo "::warning::gdb and elfutils are not installed: the stall capture's native stacks are missing"
exit 0
