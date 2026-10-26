#!/usr/bin/env bash
# A font with Japanese characters for the browser's pages (bats-lang/pwa#226,
# bats-lang/quire#907): IPAGothic, the font Playwright's own dependency list
# names for Ubuntu 24.04, 3.5 MB where fonts-noto-cjk is 61 MB from an apt
# mirror some runners reach at 55 kB/s. keyword: japanese-font
# (.claude/rules/e2e-setup.md).
#
#   japanese-font.sh key      writes `key=<cache key>` to $GITHUB_OUTPUT
#   japanese-font.sh install  puts the fonts in ~/.local/share/fonts
#
# The fonts are kept in $FONT_DIR (the directory actions/cache restores and
# saves under the key). A restored directory is judged by the SHA-256 of its
# two files, never by the key that found it; one that fails is fetched again.
# The deb is fetched by URL (no apt, no sudo) and checked against the SHA-256
# of Ubuntu's own `Packages` index for noble. A download or a hash that fails
# fails the step: the font is never silently missing.
# E2E_FONT_URLS, E2E_FONT_DEB_SHA256 and E2E_FONT_FILES_SHA256 are for the
# tests only (tests/e2e-setup/check.sh).
set -eu
package=fonts-ipafont-gothic
version=00303-21ubuntu1
deb_sha256=${E2E_FONT_DEB_SHA256:-71e63f0f88cca672fbb24ed27873d799d8c37233f001aa0bbcdc2f303b1b98a2}
files_sha256=${E2E_FONT_FILES_SHA256:-"503af4a8b84d1079b8e2e358dc7f7a7fb8cb7a1f212f35eaef6782dbfc75a55e  ipag.ttf
a63f6153841e56ec9df1b31a54d98d3f41d8aaa1c3d8df30a33502296f5b8068  ipagp.ttf"}
deb=${package}_${version}_all.deb
urls=${E2E_FONT_URLS:-"http://archive.ubuntu.com/ubuntu/pool/universe/f/fonts-ipafont/$deb https://launchpad.net/ubuntu/+archive/primary/+files/$deb"}

# fonts_ok <directory>: both files there and the pinned bytes
fonts_ok() {
  [ -d "$1" ] && (cd "$1" && printf '%s\n' "$files_sha256" | sha256sum -c - >/dev/null 2>&1)
}

case ${1:-} in
  key)
    : "${GITHUB_OUTPUT:?the step output file}"
    echo "key=japanese-font-ipafont-gothic-$version-$(printf '%.12s' "$deb_sha256")" >> "$GITHUB_OUTPUT"
    ;;
  install)
    dir=${FONT_DIR:?the directory of the cached fonts}
    if fonts_ok "$dir"; then
      echo "Japanese font: $package $version from the cache, nothing downloaded"
    else
      rm -rf "$dir"
      work=$(mktemp -d)
      fetched=no
      for url in $urls; do
        if curl -fsSL --retry 3 --retry-all-errors --connect-timeout 20 --max-time 300 -o "$work/$deb" "$url" \
           && echo "$deb_sha256  $work/$deb" | sha256sum -c - >/dev/null 2>&1; then
          fetched=yes; break
        fi
        echo "::warning::$url: not fetched, or not the file pinned by SHA-256"
      done
      [ "$fetched" = yes ] || { echo "::error::$package $version could not be fetched from any URL: the pages would show empty boxes for Japanese"; exit 1; }
      dpkg-deb -x "$work/$deb" "$work/files"
      mkdir -p "$dir"
      cp "$work"/files/usr/share/fonts/opentype/ipafont-gothic/*.ttf "$dir/"
      fonts_ok "$dir" || { echo "::error::the fonts of $package $version are not the pinned bytes"; rm -rf "$dir"; exit 1; }
      rm -rf "$work"
      echo "Japanese font: $package $version downloaded"
    fi
    target=${HOME:?}/.local/share/fonts/pwa-e2e-japanese
    mkdir -p "$target"
    cp -f "$dir"/*.ttf "$target/"
    if command -v fc-cache >/dev/null; then
      fc-cache -f "$target"
      # judged by the file: a font the machine had already must not pass for ours
      fc-list -f '%{file}\n' :lang=ja | grep -qF "$target/" \
        || { echo "::error::fontconfig lists no Japanese font after the install"; exit 1; }
    fi
    ;;
  *)
    echo "usage: japanese-font.sh key|install" >&2
    exit 2
    ;;
esac
