#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/api-docs-smoke.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

# --- upsert_body.sh ---
body="$tmpdir/body.md"
printf '%s\n' "## Purpose" "" "hello" >"$body"
out="$("$root/upsert-pr-body/upsert_body.sh" \
  --body-file "$body" \
  --main-url "https://example.github.io/repo/docs/" \
  --pr-url "https://example.github.io/repo/pr-preview/pr-1/docs/")"
grep -q 'api-docs-preview:start' <<<"$out"
grep -q 'This PR: https://example.github.io/repo/pr-preview/pr-1/docs/' <<<"$out"
grep -q 'hello' <<<"$out"
[[ "$(tail -n1 <<<"$out")" == "<!-- api-docs-preview:end -->" ]]

printf '%s\n' "$out" >"$body"
out2="$("$root/upsert-pr-body/upsert_body.sh" \
  --body-file "$body" \
  --main-url "https://example.github.io/repo/docs/" \
  --pr-url "https://example.github.io/repo/pr-preview/pr-2/docs/")"
grep -q 'pr-2' <<<"$out2"
[[ "$(grep -c 'api-docs-preview:start' <<<"$out2")" -eq 1 ]]

# --- build-site (swagger) ---
spec="$tmpdir/openapi.json"
cat >"$spec" <<'EOF'
{"openapi":"3.0.3","info":{"title":"Smoke","version":"0.0.1"},"paths":{}}
EOF
site="$tmpdir/site-swagger"
"$root/build-site/build.sh" --openapi "$spec" --out "$site" --title "Smoke API" --renderer swagger
[[ -f "$site/docs/index.html" ]]
[[ -f "$site/docs/openapi.json" ]]
[[ -f "$site/docs/swagger-ui-bundle.js" ]]
[[ -f "$site/.nojekyll" ]]
grep -q 'supportedSubmitMethods: \[\]' "$site/docs/index.html"
grep -q './openapi.json' "$site/docs/index.html"

# --- build-site (redocly) ---
site_redoc="$tmpdir/site-redocly"
"$root/build-site/build.sh" --openapi "$spec" --out "$site_redoc" --title "Smoke API" --renderer redocly
[[ -f "$site_redoc/docs/index.html" ]]
[[ -f "$site_redoc/docs/openapi.json" ]]
[[ ! -e "$site_redoc/docs/swagger-ui-bundle.js" ]]
grep -qiE 'redoc|rebilly' "$site_redoc/docs/index.html"

# --- build-site (both) ---
site_both="$tmpdir/site-both"
"$root/build-site/build.sh" --openapi "$spec" --out "$site_both" --title "Smoke API" --renderer both
[[ -f "$site_both/docs/swagger-ui-bundle.js" ]]
[[ -f "$site_both/redoc/index.html" ]]
grep -qiE 'redoc|rebilly' "$site_both/redoc/index.html"

# --- upsert-deployments select_ids ---
fix="$root/tests/fixtures/deployments-sample.json"
sel="$root/upsert-deployments/select_ids.sh"

# replace feat/demo: keep newest (100), delete 90 and 80
got="$("$sel" --ref feat/demo --mode replace <"$fix")"
[[ "$got" == $'90\n80' ]]

# purge feat/demo: delete all three
got="$("$sel" --ref feat/demo --mode purge <"$fix")"
[[ "$got" == $'100\n90\n80' ]]

# replace main: match short + refs/heads/main; keep 70, delete 60
got="$("$sel" --ref main --mode replace <"$fix")"
[[ "$got" == $'60' ]]

# protect main while purging a PR branch: never emit main ids
got="$("$sel" --ref feat/demo --mode purge --protect-ref main <"$fix")"
[[ "$got" == $'100\n90\n80' ]]
got="$("$sel" --ref feat/demo --mode replace --protect-ref main <"$fix")"
[[ "$got" == $'90\n80' ]]

# protect-ref equals --ref: still allow replacing old main
got="$("$sel" --ref main --mode replace --protect-ref main <"$fix")"
[[ "$got" == $'60' ]]

# empty / no match
got="$("$sel" --ref nonexistent --mode purge <"$fix")"
[[ -z "$got" ]]

# --- assemble/merge_site.sh ---
merge="$root/assemble/merge_site.sh"
chmod +x "$merge"
assert_file_eq() {
  local path="$1" want="$2"
  [[ -f "$path" ]] || { echo "error: missing $path" >&2; exit 1; }
  local got
  got="$(cat "$path")"
  [[ "$got" == "$want" ]] || {
    echo "error: $path expected '$want' got '$got'" >&2
    exit 1
  }
}

base_site="$tmpdir/site-base"
overlay_pr="$tmpdir/site-overlay-pr"
overlay_main="$tmpdir/site-overlay-main"
merged="$tmpdir/site-merged"
merged2="$tmpdir/site-merged2"
merged3="$tmpdir/site-merged3"

mkdir -p "$base_site/docs" "$base_site/pr-preview/pr-1/docs" "$base_site/pr-preview/pr-2/docs"
echo main-v1 >"$base_site/docs/index.html"
echo pr1-v1 >"$base_site/pr-preview/pr-1/docs/index.html"
echo pr2-v1 >"$base_site/pr-preview/pr-2/docs/index.html"
: >"$base_site/.nojekyll"

mkdir -p "$overlay_pr/pr-preview/pr-1/docs"
echo pr1-v2 >"$overlay_pr/pr-preview/pr-1/docs/index.html"

"$merge" --base "$base_site" --out "$merged" --overlay "$overlay_pr"
assert_file_eq "$merged/pr-preview/pr-1/docs/index.html" "pr1-v2"
assert_file_eq "$merged/pr-preview/pr-2/docs/index.html" "pr2-v1"
assert_file_eq "$merged/docs/index.html" "main-v1"
[[ -f "$merged/.nojekyll" ]]

mkdir -p "$overlay_main/docs"
echo main-v2 >"$overlay_main/docs/index.html"
: >"$overlay_main/.nojekyll"
# Same path for base and out (in-place style used by publish).
"$merge" --base "$merged" --out "$merged" --overlay "$overlay_main"
assert_file_eq "$merged/docs/index.html" "main-v2"
assert_file_eq "$merged/pr-preview/pr-1/docs/index.html" "pr1-v2"
assert_file_eq "$merged/pr-preview/pr-2/docs/index.html" "pr2-v1"

"$merge" --base "$merged" --out "$merged2" --remove-pr 1
[[ ! -e "$merged2/pr-preview/pr-1" ]]
[[ -d "$merged2/pr-preview/pr-2" ]]
assert_file_eq "$merged2/docs/index.html" "main-v2"

empty_base="$tmpdir/empty-base"
mkdir -p "$empty_base"
boot="$tmpdir/site-boot"
"$merge" --base "$empty_base" --out "$boot" --overlay "$overlay_pr"
assert_file_eq "$boot/pr-preview/pr-1/docs/index.html" "pr1-v2"
[[ ! -e "$boot/docs" ]]

# In-place remove
"$merge" --base "$merged" --out "$merged3" --overlay "$overlay_pr"
"$merge" --base "$merged3" --out "$merged3" --remove-pr 1
[[ ! -e "$merged3/pr-preview/pr-1" ]]
assert_file_eq "$merged3/pr-preview/pr-2/docs/index.html" "pr2-v1"

echo "smoke ok"
