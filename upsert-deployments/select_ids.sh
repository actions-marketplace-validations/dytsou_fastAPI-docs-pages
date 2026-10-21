#!/usr/bin/env bash
# Read a JSON array of deployments on stdin; print ids to delete (one per line).
# Usage: select_ids.sh --ref REF --mode replace|purge
set -euo pipefail

ref=""
mode=""

usage() {
  echo "Usage: $0 --ref REF --mode replace|purge" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref) ref="${2:-}"; shift 2 ;;
    --mode) mode="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -n "$ref" && -n "$mode" ]] || usage
[[ "$mode" == "replace" || "$mode" == "purge" ]] || usage

# Strip refs/heads/ for comparison; also accept full heads ref on either side.
norm_ref="${ref#refs/heads/}"

jq -r --arg ref "$norm_ref" --arg mode "$mode" '
  def n:
    if type == "string" and (startswith("refs/heads/"))
    then .[11:]
    else .
    end;
  [.[] | select((.ref | n) == $ref)]
  | if $mode == "purge" then .[]
    elif length <= 1 then empty
    else .[1:][]
    end
  | .id
'
