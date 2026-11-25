#!/usr/bin/env bash
# Builds site/dist/ from site/src/:
#   1. reads the living signals with read-only `gh` calls (latest release, CI on main, last push, licence, Homebrew cask version);
#   2. fails when the cask version differs from the release tag, because the page prints both;
#   3. fingerprints everything under assets/ plus style.css and page.js (name.<8 hex>.ext) and rewrites the references;
#   4. fills the {{PLACEHOLDERS}} in index.html with the snapshot, the build date (UTC) and the short git sha;
#   5. writes dist/deploy.json { at, sha }.
# A value that could not be read renders as "No data", never a guess. dist/ is built in a temp directory and moved into place.
set -euo pipefail
# bash 5.2 makes "&" special in ${var//pat/repl}; the values below may contain it
shopt -u patsub_replacement 2>/dev/null || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/src"
REPO="hmrdkn-labs/agent-awake"
TAP_CASK="repos/hmrdkn-labs/homebrew-tap/contents/Casks/agent-awake.rb"
NODATA="No data"

for tool in gh jq git shasum; do
  command -v "$tool" > /dev/null || { echo "build: $tool is required" >&2; exit 1; }
done

esc() { jq -rn --arg s "$1" '$s | @html'; }
fmt_date() {
  if [ -z "$1" ]; then echo "$NODATA"; return; fi
  jq -rn --arg t "$1" '$t | fromdateiso8601 | strftime("%-d\u00a0%b\u00a0%Y")' 2> /dev/null || echo "$NODATA"
}
field() { printf '%s' "$1" | jq -r "$2 // empty" 2> /dev/null || true; }

# 1. living signals (each call may fail on its own; the matching value then reads "No data")
rel_json="$(gh release view -R "$REPO" --json tagName,publishedAt,url 2> /dev/null || echo '{}')"
ci_json="$(gh run list -R "$REPO" -w ci -b main -L 1 --json conclusion,createdAt,url 2> /dev/null || echo '[]')"
repo_json="$(gh repo view "$REPO" --json pushedAt,licenseInfo 2> /dev/null || echo '{}')"
cask_rb="$( (gh api "$TAP_CASK" --jq .content 2> /dev/null | base64 -d 2> /dev/null) || true)"

tag="$(field "$rel_json" '.tagName')"
rel_at="$(field "$rel_json" '.publishedAt')"
rel_url="$(field "$rel_json" '.url')"
ci_result="$(field "$ci_json" '.[0].conclusion')"
ci_at="$(field "$ci_json" '.[0].createdAt')"
ci_url="$(field "$ci_json" '.[0].url')"
pushed="$(field "$repo_json" '.pushedAt')"
licence="$(field "$repo_json" '.licenseInfo.name')"
cask_ver="$(printf '%s\n' "$cask_rb" | sed -n 's/^[[:space:]]*version[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
ver="${tag#v}"

# 2. the page prints the brew command and the release, so they must agree
if [ -n "$ver" ] && [ -n "$cask_ver" ] && [ "$ver" != "$cask_ver" ]; then
  echo "build: the Homebrew cask is $cask_ver but the latest release is $tag. Fix the tap first." >&2
  exit 1
fi
[ -n "$ver" ] || echo "build: warning: no release read, the page will say \"$NODATA\"" >&2
[ -n "$cask_ver" ] || echo "build: warning: no cask version read, the page will say \"$NODATA\"" >&2

case "$ci_result" in
  success) ci_label="Passed" ;;
  failure) ci_label="Failed" ;;
  "") ci_label="$NODATA" ;;
  *) ci_label="$ci_result" ;;
esac

BUILD_DATE="$(jq -n 'now | strftime("%-d\u00a0%b\u00a0%Y")')"
BUILD_DATE="${BUILD_DATE//\"/}"
SHA="$(git -C "$ROOT" rev-parse --short HEAD 2> /dev/null || echo "$NODATA")"

if [ -n "$ver" ]; then DOWNLOAD_LABEL="Download $ver for Mac"; else DOWNLOAD_LABEL="Download for Mac"; fi
if [ -n "$ver" ] && [ "$ver" = "$cask_ver" ]; then
  CASK_LINE="The Homebrew cask and the latest release are both $ver, checked on $BUILD_DATE."
else
  CASK_LINE="Homebrew cask: ${cask_ver:-$NODATA}. Latest release: ${ver:-$NODATA}."
fi
RELEASE_TAG="${tag:-$NODATA}"
RELEASE_URL="${rel_url:-https://github.com/$REPO/releases}"
RELEASE_DATE="$(fmt_date "$rel_at")"
CI_RESULT="$ci_label"
CI_URL="${ci_url:-https://github.com/$REPO/actions}"
CI_DATE="$(fmt_date "$ci_at")"
PUSHED_DATE="$(fmt_date "$pushed")"
LICENCE="${licence:-$NODATA}"
PLACEHOLDERS="DOWNLOAD_LABEL CASK_LINE RELEASE_TAG RELEASE_URL RELEASE_DATE CI_RESULT CI_URL CI_DATE PUSHED_DATE LICENCE BUILD_DATE SHA"
for k in $PLACEHOLDERS; do
  printf -v "$k" '%s' "$(esc "${!k}")"
done

# 3. fingerprint assets, then the files that refer to them
OUT="$(mktemp -d "$ROOT/.dist.XXXXXX")"
MAP="$(mktemp)"
trap 'rm -rf "$OUT" "$MAP"' EXIT
mkdir -p "$OUT/assets"

hash8() { shasum -a 256 "$1" | cut -c1-8; }

while IFS= read -r -d '' f; do
  rel="${f#"$SRC"/assets/}"
  case "$rel" in
    *.txt) mkdir -p "$OUT/assets/$(dirname "$rel")"; cp "$f" "$OUT/assets/$rel"; continue ;;
  esac
  new="${rel%.*}.$(hash8 "$f").${rel##*.}"
  mkdir -p "$OUT/assets/$(dirname "$new")"
  cp "$f" "$OUT/assets/$new"
  printf '/assets/%s\t/assets/%s\n' "$rel" "$new" >> "$MAP"
done < <(find "$SRC/assets" -type f -print0 | sort -z)

# rewrite references in $1 using the map so far, write to stdout
rewrite() {
  local script
  script="$(mktemp)"
  awk -F'\t' '{ a = $1; gsub(/\./, "\\.", a); printf "s#%s#%s#g\n", a, $2 }' "$MAP" > "$script"
  sed -f "$script" "$1"
  rm -f "$script"
}

for name in style.css page.js; do
  tmp="$(mktemp)"
  rewrite "$SRC/$name" > "$tmp"
  new="${name%.*}.$(hash8 "$tmp").${name##*.}"
  mv "$tmp" "$OUT/assets/$new"
  printf '/assets/%s\t/assets/%s\n' "$name" "$new" >> "$MAP"
done

# 4. pages
for page in index.html 404.html; do
  html="$(rewrite "$SRC/$page")"
  for k in $PLACEHOLDERS; do
    html="${html//"{{$k}}"/${!k}}"
  done
  printf '%s\n' "$html" > "$OUT/$page"
done
if grep -rn '{{' "$OUT" --include='*.html'; then
  echo "build: unfilled placeholders in dist" >&2
  exit 1
fi

for f in favicon.svg apple-touch-icon.png og.png robots.txt _headers; do
  cp "$SRC/$f" "$OUT/$f"
done

# 5. deploy.json
jq -n --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sha "$SHA" '{at: $at, sha: $sha}' > "$OUT/deploy.json"

chmod -R u+rwX,go+rX "$OUT"
rm -rf "$ROOT/dist"
mv "$OUT" "$ROOT/dist"
trap 'rm -f "$MAP"' EXIT
echo "built $ROOT/dist: release ${tag:-$NODATA}, cask ${cask_ver:-$NODATA}, CI $ci_label, sha $(printf '%s' "$SHA")"
