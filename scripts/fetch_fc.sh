#!/usr/bin/env bash
# Install the fractal_clouds libraries at the version a project pins.
# Copy this file into your project's scripts/; it needs nothing else from
# this repo. See docs/using-the-libraries.md.
#
#   scripts/fetch_fc.sh            # install the version in .fc-version
#   scripts/fetch_fc.sh --check    # fail if lib/fc_*.ps differ from that release
#   scripts/fetch_fc.sh 0.2.0      # install 0.2.0, then write .fc-version
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
  ?*) ver="$1"; shift ;;
esac
[ $# -eq 0 ] || { echo "usage: $0 [--check | VERSION]" >&2; exit 2; }
if [ -z "${ver:-}" ]; then
  [ -f .fc-version ] || { echo "fetch_fc: no .fc-version (write the version to pin, e.g. 0.1.0)" >&2; exit 2; }
  ver="$(tr -d '[:space:]' < .fc-version)"
fi
ver="${ver#v}"
if ! [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
  echo "fetch_fc: '$ver' is not a version (MAJOR.MINOR.PATCH)" >&2; exit 2
fi
name="fractal_clouds-$ver"

tmp="$(mktemp -d)"
installing=0
# on any exit: a half-done install is rolled back to the libraries it replaced
trap 'rc=$?; if [ "$installing" = 1 ]; then rm -f lib/fc_*.ps; mv lib/.fc_old/fc_*.ps lib/ 2>/dev/null || true; fi; rm -rf lib/.fc_new lib/.fc_old "$tmp"; exit $rc' EXIT
if [ -n "${FC_FROM:-}" ]; then
  cp "$FC_FROM/$name.tar.gz" "$FC_FROM/SHA256SUMS" "$tmp/"
elif command -v gh >/dev/null; then
  # gh needs a login (gh auth login, or GH_TOKEN in CI); the repo is public,
  # so without gh plain curl works
  gh release download "v$ver" -R "$repo" -p "$name.tar.gz" -p SHA256SUMS -D "$tmp"
else
  for f in "$name.tar.gz" SHA256SUMS; do
    curl -fsSL -o "$tmp/$f" "https://github.com/$repo/releases/download/v$ver/$f"
  done
fi
if command -v sha256sum >/dev/null; then sum=sha256sum; else sum="shasum -a 256"; fi
# check exactly this archive's line, so a manifest that doesn't list it fails
# (some sha256sum builds accept --ignore-missing when nothing was checked)
awk -v n="$name.tar.gz" '$2 == n || $2 == "*" n { print; found = 1 } END { exit !found }' "$tmp/SHA256SUMS" > "$tmp/this.sum" || { echo "fetch_fc: SHA256SUMS has no entry for $name.tar.gz" >&2; exit 1; }
(cd "$tmp" && $sum -c this.sum)
mkdir "$tmp/x"
tar -xzf "$tmp/$name.tar.gz" -C "$tmp/x"
rel="$tmp/x/$name"
[ "$(cat "$rel/VERSION" 2>/dev/null)" = "$ver" ] || { echo "fetch_fc: the archive is not version $ver" >&2; exit 1; }
for f in lib/fc_landscape.ps lib/fc_presets.ps docs/settings.md docs/techniques.html PSCAT_VERSION; do
  [ -f "$rel/$f" ] || { echo "fetch_fc: the archive has no $f" >&2; exit 1; }
done

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

# stage the new libraries, move the old ones aside, swap; the trap undoes it
rm -rf lib/.fc_new lib/.fc_old
mkdir -p lib/.fc_new lib/.fc_old docs/fractal_clouds
cp "$rel"/lib/fc_*.ps lib/.fc_new/
installing=1
mv lib/fc_*.ps lib/.fc_old/ 2>/dev/null || true
mv lib/.fc_new/fc_*.ps lib/
cp "$rel/VERSION" "$rel/PSCAT_VERSION" "$rel/docs/settings.md" "$rel/docs/techniques.html" docs/fractal_clouds/
echo "$ver" > .fc-version
installing=0
echo "fetch_fc: installed fractal_clouds $ver in lib/ and docs/fractal_clouds/ (pinned in .fc-version)"

# the release was tested with one pscat; renders only reproduce on the same one
if [ -f .pscat-version ] && [ "$(cat "$rel/PSCAT_VERSION")" != "$(cat .pscat-version)" ]; then
  echo "fetch_fc: note: $ver was released with pscat $(cat "$rel/PSCAT_VERSION"); this project pins $(cat .pscat-version)" >&2
fi
