#!/usr/bin/env bash
# Pick the newest eligible github-pages artifact id from a JSON array on stdin.
#
# Usage:
#   select_pages_artifact.sh [--name NAME] [--exclude-run-id ID]
#
# stdin: JSON array of artifact objects with at least:
#   id, name, workflow_run.id (or workflow_run_id), created_at, expired
# Prints the chosen artifact id, or empty if none.
set -euo pipefail

name="github-pages"
exclude_run_id=""

usage() {
  echo "Usage: $0 [--name NAME] [--exclude-run-id ID]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) name="${2:-}"; shift 2 ;;
    --exclude-run-id) exclude_run_id="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

jq -r --arg name "$name" --arg exclude "$exclude_run_id" '
  def run_id:
    if (.workflow_run | type) == "object" then .workflow_run.id
    else .workflow_run_id
    end;
  [ .[]
    | select(.name == $name)
    | select((.expired | not) and (.expired != true))
    | select(($exclude == "") or ((run_id | tostring) != $exclude))
  ]
  | sort_by(.created_at)
  | reverse
  | .[0].id // empty
'
