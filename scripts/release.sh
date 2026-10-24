#!/usr/bin/env bash
# Build a release of the landscape libraries from the committed tree (HEAD).
#
#   scripts/release.sh 0.1.0            # writes dist/ (git-ignored)
#
# dist/ gets
#   fractal_clouds-VERSION.tar.gz            lib/fc_*.ps, docs/settings.md,
#                                            docs/techniques.html (one file,
#                                            images inlined), LICENSE, VERSION,
#                                            PSCAT_VERSION; all under one
#                                            top-level fractal_clouds-VERSION/
#   fractal_clouds-VERSION-techniques.html   the same page, to read without
#                                            unpacking anything
#   SHA256SUMS                               for both
#
# The release workflow (.github/workflows/release.yml) runs this when a `v*`
# tag is pushed and attaches dist/ to the GitHub release. A person cuts the
# first release: see docs/using-the-libraries.md ("Cutting a release").
# VERSION is MAJOR.MINOR.PATCH, optionally with a -prerelease suffix.
set -euo pipefail
cd "$(dirname "$0")/.."

ver="${1:-}"
if ! [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
  echo "usage: scripts/release.sh MAJOR.MINOR.PATCH[-pre]   (no leading v)" >&2
  exit 2
fi
repo="${FC_REPO:-ArtColony/fractal_clouds}"
name="fractal_clouds-$ver"

scripts/check_names.sh
if [ -n "$(git status --porcelain -- lib docs gallery/previews LICENSE .pscat-version)" ]; then
  echo "release: uncommitted changes in the released files; the release is built from HEAD" >&2
fi

rm -rf dist
mkdir -p dist
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# the committed tree, with the images techniques.html points at
mkdir "$work/src"
git archive HEAD lib docs gallery/previews LICENSE .pscat-version | tar -x -C "$work/src"

stage="$work/$name"
mkdir -p "$stage/docs" "$stage/lib"
cp "$work"/src/lib/fc_*.ps "$stage/lib/"
cp "$work/src/LICENSE" "$stage/"
cp "$work/src/docs/settings.md" "$stage/docs/"
python3 -I scripts/standalone_html.py "$work/src" "$stage/docs/techniques.html" \
  "https://github.com/$repo/blob/v$ver/docs"
echo "$ver" > "$stage/VERSION"
cp "$work/src/.pscat-version" "$stage/PSCAT_VERSION"

# lib/ must hold fc_ libraries only (a consumer's own libraries live beside them)
if [ "$(ls "$work/src/lib" | wc -l)" != "$(ls "$stage/lib" | wc -l)" ]; then
  echo "release: lib/ holds a file that is not fc_*.ps" >&2; exit 1
fi

COPYFILE_DISABLE=1 tar -C "$work" -cf - "$name" | gzip -n -9 > "dist/$name.tar.gz"
cp "$stage/docs/techniques.html" "dist/$name-techniques.html"
if command -v sha256sum >/dev/null; then sum=sha256sum; else sum="shasum -a 256"; fi
(cd dist && $sum "$name.tar.gz" "$name-techniques.html" > SHA256SUMS)

echo "release: dist/ for $ver"
ls -l dist
cat dist/SHA256SUMS
