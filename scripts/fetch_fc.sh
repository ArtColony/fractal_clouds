#!/usr/bin/env bash
# Install the fractal_clouds libraries at the version a project pins.
# Copy this file into your project's scripts/; it needs nothing else from
# this repo. See docs/using-the-libraries.md.
#
#   scripts/fetch_fc.sh            # install the version in .fc-version
#   scripts/fetch_fc.sh --check    # fail if lib/fc_*.ps differ from that release
#   scripts/fetch_fc.sh 0.2.0      # write .fc-version, then install
#
# Run from anywhere; it works on the project root (the directory above
# scripts/). It puts
#   lib/fc_*.ps                    the libraries (the libraries load each other
#                                  as (lib/fc_x.ps), relative to the directory
#                                  you render from, so they must sit in lib/)
#   docs/fractal_clouds/           VERSION, PSCAT_VERSION, settings.md and
#                                  techniques.html of that release
# and replaces the lib/fc_*.ps already there, so a file a release dropped
# goes too. Don't keep your own libraries under the fc_ prefix. Commit the
# result, or git-ignore it and run this script in setup and CI: either way
# the version is the one in .fc-version.
#
# Environment: FC_REPO (default ArtColony/fractal_clouds), FC_FROM=DIR to use
# a release's files (tarball and SHA256SUMS) from a local directory instead of
# downloading them with gh, which is what the release workflow's output
# looks like.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

repo="${FC_REPO:-ArtColony/fractal_clouds}"
check=0
case "${1:-}" in
  --check) check=1; shift ;;
  -*) echo "usage: $0 [--check | VERSION]" >&2; exit 2 ;;
  ?*) echo "$1" > .fc-version; shift ;;
esac
[ -f .fc-version ] || { echo "fetch_fc: no .fc-version (write the version to pin, e.g. 0.1.0)" >&2; exit 2; }
ver="$(tr -d '[:space:]' < .fc-version)"
ver="${ver#v}"
name="fractal_clouds-$ver"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
if [ -n "${FC_FROM:-}" ]; then
  cp "$FC_FROM/$name.tar.gz" "$FC_FROM/SHA256SUMS" "$tmp/"
else
  gh release download "v$ver" -R "$repo" -p "$name.tar.gz" -p SHA256SUMS -D "$tmp"
fi
if command -v sha256sum >/dev/null; then sum=sha256sum; else sum="shasum -a 256"; fi
(cd "$tmp" && $sum -c SHA256SUMS --ignore-missing)
tar -xzf "$tmp/$name.tar.gz" -C "$tmp"
rel="$tmp/$name"
[ "$(cat "$rel/VERSION")" = "$ver" ] || { echo "fetch_fc: the archive is not version $ver" >&2; exit 1; }

if [ "$check" = 1 ]; then
  status=0
  for f in "$rel"/lib/fc_*.ps; do
    cmp -s "$f" "lib/$(basename "$f")" || { echo "fetch_fc: lib/$(basename "$f") differs from $ver" >&2; status=1; }
  done
  for f in lib/fc_*.ps; do
    [ -e "$rel/$f" ] || { echo "fetch_fc: $f is not in $ver" >&2; status=1; }
  done
  [ "$status" = 0 ] && echo "fetch_fc: lib/fc_*.ps are fractal_clouds $ver"
  exit "$status"
fi

mkdir -p lib docs/fractal_clouds
rm -f lib/fc_*.ps
cp "$rel"/lib/fc_*.ps lib/
cp "$rel/VERSION" "$rel/PSCAT_VERSION" "$rel/docs/settings.md" "$rel/docs/techniques.html" docs/fractal_clouds/
echo "fetch_fc: installed fractal_clouds $ver in lib/ and docs/fractal_clouds/"

# the release was tested with one pscat; renders only reproduce on the same one
if [ -f .pscat-version ] && [ "$(cat "$rel/PSCAT_VERSION")" != "$(cat .pscat-version)" ]; then
  echo "fetch_fc: note: $ver was released with pscat $(cat "$rel/PSCAT_VERSION"); this project pins $(cat .pscat-version)" >&2
fi
