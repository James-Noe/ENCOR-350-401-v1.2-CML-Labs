#!/bin/bash
# CML REST helpers: native topology export/import, plus compact read-only
# queries that replace the token-heavy MCP calls (STANDARDS §11).
#
# export/import: use these instead of cml-mcp's download_lab_topology. The MCP
# output is not the native format (it rewrites annotation `border_style: ''`
# to `solid`, which /import rejects with HTTP 400). Found by the LAB-002/004
# builders, 2026-09-26.
#
# The query commands print one short line per item. The state-changing ones
# (start/stop/wipe/delete/title/node/link) replace the matching cml-mcp tools,
# so build and validate agents need no MCP tool schemas for lab lifecycle. They replace
# get_cml_labs / get_cml_statistics / get_nodes_for_cml_lab (~5 KB per call),
# get_all_links_for_lab, raw get_console_log (~18 KB) and sleep-polling for
# BOOTED.
#
# Usage:
#   cml-rest.sh export <lab> <out.yaml>    native YAML of the stored (day-0) state
#   cml-rest.sh import <file.yaml>         prints the new lab id
#   cml-rest.sh labs                       id  state  nodes  title (one line per lab)
#   cml-rest.sh budget                     running nodes across all labs, of the 20 licensed
#   cml-rest.sh nodes <lab>                label  state  node_definition  node_id
#   cml-rest.sh links <lab>                nodeA-intf<->nodeB-intf  state  link_id
#   cml-rest.sh wait <lab> [timeout_s]     block until every node is BOOTED (default 240 s,
#                                          under the 5-min subagent cache; re-run until booted);
#                                          one line out, exit 1 on timeout. Run it with a Bash
#                                          timeout above timeout_s. VM images (boot timeout
#                                          >= 250 s: cat8000v, csr1000v, cat9000v, iosvl2, ...)
#                                          also need a ready line in their console log: CML
#                                          marks them BOOTED when that timeout expires, not
#                                          when they are ready (cat8000v: BOOTED 266 s, CLI
#                                          usable 487 s, measured 2026-10-05). cat8000v and
#                                          csr1000v also need the day-0 config applied
#                                          (%SYS-5-CONFIG_P or %CVAC-4-CONFIG_DONE), after the
#                                          last reload in the log. A day-0 licence change
#                                          reloads once a few seconds after its config line:
#                                          confirm with `show version | include uptime`.
#   cml-rest.sh log <lab> <label> [lines] [regex] [console]
#                                          last <lines> (default 40) console-log lines,
#                                          optionally filtered by an extended regex first
#   cml-rest.sh start|stop|wipe|delete <lab>   whole-lab state change (delete stops and wipes first)
#   cml-rest.sh title <lab> <new title>        retitle (replaces MCP modify_cml_lab)
#   cml-rest.sh node start|stop|wipe <lab> <label>
#   cml-rest.sh link start|stop <lab> <link label>   label as printed by `links`
# <lab> is a lab id or an exact lab title. The state-changing commands refuse any
# lab whose title doesn't start with ENCOR (other labs belong to the user).
# Needs CML_URL, CML_USERNAME, CML_PASSWORD (set in the devcontainer), curl, jq.
# A failed import can still leave an empty orphan lab: list labs and delete it.
set -euo pipefail
: "${CML_URL:?CML_URL not set}" "${CML_USERNAME:?}" "${CML_PASSWORD:?}"
token() {
  curl -skf -X POST "$CML_URL/api/v0/authenticate" -H 'Content-Type: application/json' \
    -d "$(jq -n --arg u "$CML_USERNAME" --arg p "$CML_PASSWORD" '{username:$u,password:$p}')" | tr -d '"'
}
get() { curl -skf -H "Authorization: Bearer $TOKEN" "$CML_URL/api/v0/$1"; }
# call METHOD PATH [JSON]: state-changing request, output discarded, fails loudly
call() {
  local body=()
  [ $# -ge 3 ] && body=(-H 'Content-Type: application/json' -d "$3")
  curl -skf -o /dev/null -X "$1" -H "Authorization: Bearer $TOKEN" "${body[@]}" \
    "$CML_URL/api/v0/$2" || { echo "$1 $2 failed" >&2; exit 1; }
}
# ours <lab>: resolve to an id, refusing labs not titled ENCOR*
ours() {
  local id title; id=$(lab_id "$1"); title=$(get "labs/$id" | jq -r .lab_title)
  [[ $title == ENCOR* ]] || { echo "refusing: '$title' is not an ENCOR lab" >&2; exit 1; }
  echo "$id"
}
node_id() {
  local nid; nid=$(get "labs/$1/nodes?data=true" | jq -r --arg l "$2" '.[] | select(.label == $l) | .id')
  [ -n "$nid" ] || { echo "no node labelled '$2'" >&2; exit 1; }
  echo "$nid"
}
lab_ids() { get labs | jq -r '.[]'; }
# Resolve a lab id or exact title to an id.
lab_id() {
  if [[ $1 =~ ^[0-9a-f]{8}-[0-9a-f-]{27}$ ]]; then echo "$1"; return; fi
  local id
  for id in $(lab_ids); do
    [ "$(get "labs/$id" | jq -r .lab_title)" = "$1" ] && { echo "$id"; return; }
  done
  echo "no lab titled '$1'" >&2; exit 1
}
usage() { sed -n '/^# Usage:/,/^# Needs/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

cmd=${1:-}; [ -n "$cmd" ] || usage; shift
TOKEN=$(token)
case "$cmd" in
  export)
    [ $# -eq 2 ] || usage
    get "labs/$(lab_id "$1")/download" > "$2" ;;
  import)
    [ $# -eq 1 ] || usage
    curl -skf -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/x-yaml' \
      --data-binary @"$1" "$CML_URL/api/v0/import"; echo ;;
  labs)
    for id in $(lab_ids); do
      get "labs/$id" | jq -r '[.id, .state, (.node_count|tostring), .lab_title] | join("  ")'
    done ;;
  budget)
    n=0
    for id in $(lab_ids); do
      n=$((n + $(get "labs/$id/nodes?data=true" | jq '[.[] | select(.state != "STOPPED" and .state != "DEFINED_ON_CORE")] | length')))
    done
    echo "running nodes: $n / 20" ;;
  nodes)
    [ $# -eq 1 ] || usage
    get "labs/$(lab_id "$1")/nodes?data=true" |
      jq -r '.[] | [.label, .state, .node_definition, .id] | join("  ")' ;;
  links)
    [ $# -eq 1 ] || usage
    get "labs/$(lab_id "$1")/links?data=true" | jq -r '.[] | [.label, .state, .id] | join("  ")' ;;
  wait)
    [ $# -ge 1 ] || usage
    id=$(lab_id "$1"); timeout=${2:-240}; start=$SECONDS
    # node definition -> ready lines, for definitions whose BOOTED can be a timeout
    slow=$(get node_definitions | jq -c '[.[] | select(.boot.timeout >= 250)
      | {key: .id, value: (.boot.completed // [])}] | from_entries')
    declare -A ready=()
    while :; do
      nodes=$(get "labs/$id/nodes?data=true")
      states=$(jq -r '.[] | "\(.label)=\(.state)"' <<<"$nodes")
      pending=$(grep -v '=BOOTED$' <<<"$states" || true)
      if [ -z "$pending" ]; then
        checked=0
        while IFS=$'\t' read -r label nid def; do
          lines=$(jq -r --arg d "$def" '.[$d] // empty | .[]' <<<"$slow")
          [ -n "$lines" ] || [ "$(jq -r --arg d "$def" 'has($d)' <<<"$slow")" = true ] || continue
          checked=$((checked + 1))
          [ -n "${ready[$label]:-}" ] && continue
          # only what follows the last reload (a licence change in day-0 reloads once)
          log=$(get "labs/$id/nodes/$nid/consoles/0/log" | jq -r . 2>/dev/null \
            | awk '/%SYS-5-RELOAD|Reload requested/ {buf = ""} {buf = buf $0 "\n"} END {printf "%s", buf}' || true)
          ok=1
          if [ -n "$lines" ] && ! grep -qF -- "$lines" <<<"$log"; then ok=0; fi
          case $def in cat8000v|csr1000v)
            grep -qE '%SYS-5-CONFIG_P|%CVAC-4-CONFIG_DONE' <<<"$log" || ok=0 ;;
          esac
          if [ $ok = 1 ]; then ready[$label]=1; else pending+="$label=BOOTED-not-ready"$'\n'; fi
        done < <(jq -r '.[] | "\(.label)\t\(.id)\t\(.node_definition)"' <<<"$nodes")
        if [ -z "$pending" ]; then
          note=""; [ $checked -gt 0 ] && note=" ($checked VM nodes with console ready lines)"
          echo "all $(wc -l <<<"$states") nodes BOOTED after $((SECONDS - start)) s$note"; exit 0
        fi
      fi
      if (( SECONDS - start >= timeout )); then
        echo "timeout after ${timeout} s; not booted: $(tr '\n' ' ' <<<"$pending")"; exit 1
      fi
      sleep 10
    done ;;
  log)
    [ $# -ge 2 ] || usage
    id=$(lab_id "$1"); lines=${3:-40}; regex=${4:-}; console=${5:-0}
    node=$(get "labs/$id/nodes?data=true" | jq -r --arg l "$2" '.[] | select(.label == $l) | .id')
    [ -n "$node" ] || { echo "no node labelled '$2'" >&2; exit 1; }
    out=$(get "labs/$id/nodes/$node/consoles/$console/log" | jq -r .) ||
      { echo "no log for '$2' console $console (node stopped, or no such console)" >&2; exit 1; }
    if [ -n "$regex" ]; then out=$(grep -E -- "$regex" <<<"$out" || true); fi
    tail -n "$lines" <<<"$out" ;;
  start|stop|wipe)
    [ $# -eq 1 ] || usage
    id=$(ours "$1"); call PUT "labs/$id/$cmd"; echo "$cmd: $1" ;;
  delete)
    [ $# -eq 1 ] || usage
    id=$(ours "$1")
    state=$(get "labs/$id" | jq -r .state)
    [ "$state" = STOPPED ] || [ "$state" = DEFINED_ON_CORE ] || call PUT "labs/$id/stop"
    [ "$state" = DEFINED_ON_CORE ] || call PUT "labs/$id/wipe"
    call DELETE "labs/$id"; echo "deleted: $1" ;;
  title)
    [ $# -eq 2 ] || usage
    id=$(ours "$1"); [[ $2 == ENCOR* ]] || { echo "new title must start with ENCOR" >&2; exit 1; }
    call PATCH "labs/$id" "$(jq -n --arg t "$2" '{title:$t}')"; echo "title: $2" ;;
  node)
    [ $# -eq 3 ] || usage
    id=$(ours "$2"); nid=$(node_id "$id" "$3")
    case "$1" in
      start|stop) call PUT "labs/$id/nodes/$nid/state/$1" ;;
      wipe) call PUT "labs/$id/nodes/$nid/wipe_disks" ;;
      *) usage ;;
    esac
    echo "node $1: $3" ;;
  link)
    [ $# -eq 3 ] || usage
    case "$1" in start|stop) ;; *) usage ;; esac
    id=$(ours "$2")
    lid=$(get "labs/$id/links?data=true" | jq -r --arg l "$3" '.[] | select(.label == $l) | .id')
    [ -n "$lid" ] || { echo "no link labelled '$3' (see: links $2)" >&2; exit 1; }
    call PUT "labs/$id/links/$lid/state/$1"; echo "link $1: $3" ;;
  *) usage ;;
esac
