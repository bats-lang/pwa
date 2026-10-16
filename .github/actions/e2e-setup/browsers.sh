#!/usr/bin/env bash
# Install Playwright's headless Chromium into $PLAYWRIGHT_BROWSERS_PATH,
# again when the download's connection drops. Chromium alone, as gen-pwa
# test checks for it (chromium_headless_shell-<revision>). With the
# directory restored from the cache this finds it complete and downloads
# nothing. Run in the directory of node_modules.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
. "$here/retry.sh"
: "${PLAYWRIGHT_BROWSERS_PATH:?the browsers directory}"
mkdir -p "$PLAYWRIGHT_BROWSERS_PATH"
[ -x node_modules/.bin/playwright ] || { echo "::error::node_modules/.bin/playwright is not there"; exit 1; }
retry "playwright install" node_modules/.bin/playwright install chromium
