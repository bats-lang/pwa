#!/usr/bin/env bash
# Read the installed Playwright version (node_modules/playwright-core, the
# package that holds browsers.json), refuse one older than
# $PLAYWRIGHT_MINIMUM (major.minor), and write the step outputs
# version, browsers (the directory, $BROWSERS_PATH) and browsers-key
# ($KEY_PREFIX and the version) to $GITHUB_OUTPUT, and
# PLAYWRIGHT_BROWSERS_PATH to $GITHUB_ENV, when they are set.
#
# The browsers' key is the Playwright version alone: a revision of
# Chromium belongs to one version (browsers.json), so the key changes when
# the lock moves Playwright and at no other time, and not with the app.
set -eu
json=node_modules/playwright-core/package.json
[ -f "$json" ] || { echo "::error::node_modules/playwright-core is not there: does package.json depend on @playwright/test?"; exit 1; }
version=$(node -e 'console.log(require("./node_modules/playwright-core/package.json").version)')
case $version in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "::error::cannot read a version from '$version'"; exit 1 ;;
esac

if [ -n "${PLAYWRIGHT_MINIMUM:-}" ]; then
  case $PLAYWRIGHT_MINIMUM in
    [0-9]*.[0-9]*) ;;
    *) echo "::error::playwright-minimum '$PLAYWRIGHT_MINIMUM' is not major.minor"; exit 1 ;;
  esac
  lowest=$(printf '%s\n%s\n' "$PLAYWRIGHT_MINIMUM" "$version" | sort -V | head -n 1)
  if [ "$lowest" != "$PLAYWRIGHT_MINIMUM" ] && [ "$version" != "$PLAYWRIGHT_MINIMUM" ]; then
    echo "::error::package-lock.json installs Playwright $version, older than the $PLAYWRIGHT_MINIMUM the suite needs; update the lock"
    exit 1
  fi
fi

echo "Playwright $version"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "version=$version"
    echo "browsers=${BROWSERS_PATH:-$HOME/.cache/ms-playwright}"
    echo "browsers-key=${KEY_PREFIX:-playwright-browsers-}$version"
  } >> "$GITHUB_OUTPUT"
fi
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "PLAYWRIGHT_BROWSERS_PATH=${BROWSERS_PATH:-$HOME/.cache/ms-playwright}" >> "$GITHUB_ENV"
fi
