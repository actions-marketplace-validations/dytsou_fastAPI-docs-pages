#!/usr/bin/env bash
# Upsert API docs preview links at the end of a PR description.
# CI owns the marker block; do not put markers in the PR template.
# Usage:
#   upsert_body.sh --body-file FILE --main-url URL [--pr-url URL] [--removed]
# Writes updated body to stdout.
set -euo pipefail

START='<!-- api-docs-preview:start -->'
END='<!-- api-docs-preview:end -->'

body_file=""
main_url=""
pr_url=""
removed=0

usage() {
  echo "Usage: $0 --body-file FILE --main-url URL [--pr-url URL] [--removed]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --body-file) body_file="${2:-}"; shift 2 ;;
    --main-url) main_url="${2:-}"; shift 2 ;;
    --pr-url) pr_url="${2:-}"; shift 2 ;;
    --removed) removed=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$body_file" && -n "$main_url" && -f "$body_file" ]] || usage

block_file="$(mktemp "${TMPDIR:-/tmp}/api-docs-block.XXXXXX")"
cleanup() { rm -f "$block_file"; }
trap cleanup EXIT

{
  echo "$START"
  if [[ "$removed" -eq 1 ]]; then
    echo "**API docs preview:** removed (PR closed)."
  else
    echo "**API docs preview**"
    echo "- Main: ${main_url}"
    if [[ -n "$pr_url" ]]; then
      echo "- This PR: ${pr_url}"
    fi
  fi
  echo "$END"
} >"$block_file"

body_file_abs="$(cd "$(dirname "$body_file")" && pwd -P)/$(basename "$body_file")"

if grep -Fq "$START" "$body_file_abs" && grep -Fq "$END" "$body_file_abs"; then
  awk -v start="$START" -v end="$END" -v block_file="$block_file" '
    BEGIN { in_block = 0 }
    index($0, start) {
      while ((getline line < block_file) > 0) print line
      close(block_file)
      in_block = 1
      next
    }
    in_block && index($0, end) { in_block = 0; next }
    !in_block { print }
  ' "$body_file_abs"
  exit 0
fi

body="$(cat "$body_file_abs")"
if [[ -n "$body" ]]; then
  printf '%s\n\n' "$body"
fi
cat "$block_file"
