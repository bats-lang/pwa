# Sourced by npm-ci.sh and browsers.sh: run a command, again when it failed
# because the network did, with a pause that doubles.
#
#   retry <label> <command> [args...]
#
# Retried only on the failures of a download: a connection that dropped
# (npm's and Playwright's own words for them, below), or an archive cut
# short, which sdkmanager reports as "Error on ZipFile unknown archive"
# and still exits 0 (bats-lang/quire#617). A lock that does not match
# package.json, a version that does not exist or a missing file fails at
# once, since a second try cannot change it. E2E_ATTEMPTS (default 3) is
# the number of tries, E2E_PAUSE_S (default 15) the first pause; the tests
# set both small.

NETWORK_FAILURE='code (ECONNRESET|ECONNREFUSED|ECONNABORTED|ETIMEDOUT|ESOCKETTIMEDOUT|EAI_AGAIN|ENOTFOUND|EPIPE|EHOSTUNREACH|ENETUNREACH|FETCH_ERROR|E429|E50[0-9])|network (read|timeout|socket)|socket hang up|Download failed|ECONNRESET|ETIMEDOUT|EAI_AGAIN|ZipFile unknown archive'

retry() {
  label=$1; shift
  attempts=${E2E_ATTEMPTS:-3}
  pause=${E2E_PAUSE_S:-15}
  log=$(mktemp)
  n=1
  while :; do
    # the command's own output stays visible and is kept to be read; tee's
    # status is not the command's, PIPESTATUS (bash) is
    "$@" 2>&1 | tee "$log"
    status=${PIPESTATUS[0]}
    if [ "$status" = 0 ]; then rm -f "$log"; return 0; fi
    if ! grep -Eq "$NETWORK_FAILURE" "$log"; then
      echo "::error::$label failed, and not from the network: trying again would change nothing"
      rm -f "$log"; return "$status"
    fi
    if [ "$n" -ge "$attempts" ]; then
      echo "::error::$label failed $attempts times on a download (the connection dropped, or an archive was cut short, each time); nothing was tested"
      rm -f "$log"; return "$status"
    fi
    echo "::warning::$label: the download failed (try $n of $attempts); again in ${pause}s"
    sleep "$pause"
    pause=$((pause * 2)); n=$((n + 1))
  done
}
