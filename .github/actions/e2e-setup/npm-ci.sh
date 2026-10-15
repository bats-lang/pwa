#!/usr/bin/env bash
# Install exactly package-lock.json in the current directory.
#
# npm ci installs the lock and nothing else: it fails when the lock does
# not match package.json and never rewrites either. npm already retries
# each request (fetch-retries, default 2, 10 s to 60 s apart; npm's
# config documentation); a dropped connection that outlasts those tries
# (quire#635: ECONNRESET, after which nothing had run for 16 minutes)
# runs the whole install again, which is safe since npm ci removes
# node_modules first. The tests set E2E_NPM_RETRY_MIN_MS and
# E2E_NPM_RETRY_MAX_MS small.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
. "$here/retry.sh"

[ -f package.json ] || { echo "::error::no package.json in $(pwd)"; exit 1; }
[ -f package-lock.json ] || { echo "::error::no package-lock.json in $(pwd): run npm install and commit the lock; the e2e jobs install exactly it"; exit 1; }

retry "npm ci" npm ci --no-audit --no-fund \
  --fetch-retries="${E2E_NPM_FETCH_RETRIES:-5}" \
  --fetch-retry-mintimeout="${E2E_NPM_RETRY_MIN_MS:-10000}" \
  --fetch-retry-maxtimeout="${E2E_NPM_RETRY_MAX_MS:-60000}"
