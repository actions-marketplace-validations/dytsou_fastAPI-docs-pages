#!/usr/bin/env bash
# Fetch a PR body, upsert API docs preview links, PATCH if changed.
# Usage:
#   patch.sh --owner O --repo R --pr N [--removed]
# Requires: gh, jq, and GH_TOKEN (or other gh auth).
set -euo pipefail

owner=""
repo=""
pr=""
removed=0

usage() {
  echo "Usage: $0 --owner OWNER --repo REPO --pr N [--removed]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) owner="${2:-}"; shift 2 ;;
    --repo) repo="${2:-}"; shift 2 ;;
    --pr) pr="${2:-}"; shift 2 ;;
    --removed) removed=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$owner" && -n "$repo" && -n "$pr" ]] || usage

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
pages_base="https://${owner}.github.io/${repo}"
main_url="${pages_base}/docs/"
pr_url="${pages_base}/pr-preview/pr-${pr}/docs/"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/api-docs-pr-body.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT
body_file="$tmpdir/body.md"
out_file="$tmpdir/out.md"

gh api "repos/${owner}/${repo}/pulls/${pr}" --jq '.body // empty' >"$body_file"

upsert=(
  "$script_dir/upsert_body.sh"
  --body-file "$body_file"
  --main-url "$main_url"
)
if [[ "$removed" -eq 1 ]]; then
  upsert+=(--removed)
else
  upsert+=(--pr-url "$pr_url")
fi
"${upsert[@]}" >"$out_file"

if cmp -s "$body_file" "$out_file"; then
  echo "PR body unchanged; skipping PATCH"
  exit 0
fi

jq -Rs '{body: .}' <"$out_file" \
  | gh api --method PATCH "repos/${owner}/${repo}/pulls/${pr}" --input -
