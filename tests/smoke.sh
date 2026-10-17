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

echo "smoke ok"
