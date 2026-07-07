#!/usr/bin/env bash
# schemaset.sh — create, update, and list Fabric Event Schema Sets via REST.
#
# Wraps the Fabric REST API for Event Schema Sets. Calls are made with curl; the
# bearer token comes from the Azure CLI (az), using your signed-in User identity.
#
#   create   Create a schema set from a sample (optionally inside a folder).
#              POST /v1/workspaces/{ws}/eventSchemaSets                    (workspace root)
#              POST /v1/workspaces/{ws}/items            (+ folderId)      (into a folder)
#   update   Overwrite an existing schema set's definition from a sample.
#              POST /v1/workspaces/{ws}/eventSchemaSets/{id}/updateDefinition
#   list     List schema sets, or the event types / schemas inside one.
#              GET  /v1/workspaces/{ws}/eventSchemaSets
#              POST /v1/workspaces/{ws}/eventSchemaSets/{id}/getDefinition
#
# create/update build the sample's EventSchemaSetDefinition.json first (via
# build-definition.sh) unless --no-build is given. Add --dry-run to print the
# REST call (and request body) without sending it.
#
# Prereqs: az (signed in via 'az login'), plus curl and jq.
# Docs: https://learn.microsoft.com/en-us/rest/api/fabric/eventschemaset/items
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_BASE="https://api.fabric.microsoft.com/v1"
FABRIC_RESOURCE="https://api.fabric.microsoft.com"

usage () {
  cat <<'EOF'
Create, update, and list Microsoft Fabric Event Schema Sets.

Usage:
  schemaset.sh create --workspace <guid> --sample <dir> [--folder-id <guid>] [--no-build] [--dry-run]
  schemaset.sh update --workspace <guid> --schemaset-id <guid> --sample <dir> [--no-build] [--dry-run]
  schemaset.sh list [schemasets|event-types|schemas] --workspace <guid> [--schemaset-id <guid>] [--dry-run]

Options:
  -w, --workspace <guid>     Fabric workspace ID (required).
      --sample <dir>         Sample folder (required for create/update), e.g. samples/gtfs-realtime.
  -s, --schemaset-id <guid>  Event Schema Set ID (required for update and for list event-types/schemas).
      --folder-id <guid>     Place a created item in this workspace folder (create only).
      --no-build             Don't rebuild EventSchemaSetDefinition.json first; use the existing file.
      --dry-run              Print the REST call (and body) without sending it.
  -h, --help                 Show this help and exit.

Notes:
  * Folder placement is by folder ID (a GUID). Find it in the Fabric portal URL when the
    folder is open, or via the List Folders API.
  * 'update' overwrites only the definition (schemas + event types), not the display name.

Examples:
  schemaset.sh create -w 1111-2222 --sample samples/gtfs-realtime
  schemaset.sh create -w 1111-2222 --sample samples/gtfs-realtime --folder-id 4444-5555
  schemaset.sh update -w 1111-2222 -s 6666-7777 --sample samples/gtfs-realtime
  schemaset.sh list schemasets  -w 1111-2222
  schemaset.sh list event-types -w 1111-2222 -s 6666-7777
  schemaset.sh list schemas     -w 1111-2222 -s 6666-7777
EOF
}

COMMAND="${1:-}"
case "$COMMAND" in
  create|update|list) shift ;;
  -h|--help) usage; exit 0 ;;
  "")        usage >&2; exit 2 ;;
  *)         echo "Unknown command: $COMMAND" >&2; echo >&2; usage >&2; exit 2 ;;
esac

# For 'list', an optional target follows the command (default: schemasets).
LIST_TARGET="schemasets"
if [ "$COMMAND" = list ]; then
  case "${1:-}" in
    schemasets|event-types|schemas) LIST_TARGET="$1"; shift ;;
    ""|-*) ;;  # no target given — keep default, options follow
    *) echo "Unknown list target: $1 (use schemasets|event-types|schemas)." >&2; exit 2 ;;
  esac
fi

WORKSPACE_ID=""
SCHEMASET_ID=""
SAMPLE_DIR=""
FOLDER_ID=""
NO_BUILD=""
DRY_RUN=""

while [ $# -gt 0 ]; do
  case "$1" in
    -w|--workspace)    WORKSPACE_ID="${2:?--workspace requires a value}"; shift 2 ;;
    -s|--schemaset-id) SCHEMASET_ID="${2:?--schemaset-id requires a value}"; shift 2 ;;
    --sample)          SAMPLE_DIR="${2:?--sample requires a value}"; shift 2 ;;
    --folder-id)       FOLDER_ID="${2:?--folder-id requires a value}"; shift 2 ;;
    --no-build)        NO_BUILD=1; shift ;;
    --dry-run)         DRY_RUN=1; shift ;;
    -h|--help)         usage; exit 0 ;;
    -*)                echo "Unknown option: $1" >&2; echo >&2; usage >&2; exit 2 ;;
    *)                 echo "Unexpected argument: $1" >&2; echo >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$WORKSPACE_ID" ]; then
  echo "Error: --workspace is required." >&2
  echo >&2
  usage >&2
  exit 2
fi

# Clean up any temp request-body file on exit.
BODY_TMP=""
trap '[ -n "$BODY_TMP" ] && rm -f "$BODY_TMP"' EXIT

# show METHOD ENDPOINT — print the REST request line being issued.
show () { echo "REST> $1 $API_BASE/$2"; }

# access_token — a bearer token for the Fabric API, minted by the Azure CLI.
access_token () {
  command -v az >/dev/null 2>&1 || {
    echo "Error: the Azure CLI (az) is required for authentication. Install it, then 'az login'." >&2; exit 1; }
  local t
  t="$(az account get-access-token --resource "$FABRIC_RESOURCE" --query accessToken -o tsv 2>/dev/null || true)"
  if [ -z "$t" ]; then
    echo "Error: could not get an access token. Run 'az login' first." >&2; exit 1
  fi
  printf '%s' "$t"
}

# call_api METHOD ENDPOINT [BODY_FILE] — Fabric REST call via curl (token from az).
# ENDPOINT is relative to $API_BASE. Prints the response body on success; on an
# HTTP >= 400 status it prints the status + body to stderr and exits 1.
call_api () {
  command -v curl >/dev/null 2>&1 || { echo "Error: curl is required." >&2; exit 1; }
  local method endpoint body token url resp code
  method="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  endpoint="$2"; body="${3:-}"
  token="$(access_token)"
  url="$API_BASE/$endpoint"
  local args=(-sS -X "$method" -H "Authorization: Bearer $token")
  if [ -n "$body" ]; then
    args+=(-H "Content-Type: application/json" --data-binary "@$body")
  elif [ "$method" != GET ]; then
    # Bodyless POST (e.g. getDefinition) still needs Content-Length: 0, or Fabric
    # returns HTTP 411 Length Required — send an explicit empty body.
    args+=(-H "Content-Type: application/json" --data-binary "")
  fi
  # Append the HTTP status on its own trailing line, then split it back off.
  resp="$(curl "${args[@]}" -w $'\n%{http_code}' "$url")"
  code="${resp##*$'\n'}"
  resp="${resp%$'\n'*}"
  if ! [[ "$code" =~ ^2[0-9][0-9]$ ]]; then
    echo "HTTP $code — $method $url" >&2
    if [ -n "$resp" ]; then printf '%s\n' "$resp" | jq . 2>/dev/null >&2 || printf '%s\n' "$resp" >&2; fi
    exit 1
  fi
  printf '%s' "$resp"
}

def_file () { echo "${SAMPLE_DIR%/}/EventSchemaSetDefinition.json"; }

# Ensure the sample's definition file exists (rebuild it unless --no-build).
ensure_definition () {
  if [ -z "$SAMPLE_DIR" ]; then
    echo "Error: --sample <dir> is required for '$COMMAND'." >&2; exit 2
  fi
  if [ -z "$NO_BUILD" ]; then
    bash "$SCRIPT_DIR/build-definition.sh" "$SAMPLE_DIR" >&2
  fi
  local f; f="$(def_file)"
  [ -f "$f" ] || { echo "Error: $f not found (drop --no-build to build it)." >&2; exit 1; }
}

# make_body MODE — write the request body to a temp file; sets BODY_TMP.
#   MODE = create-folder | create-root | update
make_body () {
  local mode="$1" deffile manifest name desc payload
  deffile="$(def_file)"
  manifest="${SAMPLE_DIR%/}/manifest.json"
  name="$(jq -r '.displayName // "Event Schema Set"' "$manifest")"
  desc="$(jq -r '.description // ""' "$manifest")"
  payload="$(base64 -w0 "$deffile" 2>/dev/null || base64 "$deffile" | tr -d '\n')"
  BODY_TMP="$(mktemp)"
  case "$mode" in
    create-folder)
      jq -n --arg name "$name" --arg desc "$desc" --arg fid "$FOLDER_ID" --arg payload "$payload" \
        '{ displayName: $name, type: "EventSchemaSet", description: $desc, folderId: $fid,
           definition: { parts: [ { path: "EventSchemaSetDefinition.json", payload: $payload, payloadType: "InlineBase64" } ] } }' > "$BODY_TMP" ;;
    create-root)
      jq -n --arg name "$name" --arg desc "$desc" --arg payload "$payload" \
        '{ displayName: $name, description: $desc,
           definition: { parts: [ { path: "EventSchemaSetDefinition.json", payload: $payload, payloadType: "InlineBase64" } ] } }' > "$BODY_TMP" ;;
    update)
      jq -n --arg payload "$payload" \
        '{ definition: { parts: [ { path: "EventSchemaSetDefinition.json", payload: $payload, payloadType: "InlineBase64" } ] } }' > "$BODY_TMP" ;;
  esac
}

# get_definition — Get Event Schema Set Definition and decode the JSON part.
# Event types and schemas live inside the definition; the JSON part is base64,
# so decode it with jq's @base64d (no base64 CLI needed).
get_definition () {
  call_api post "workspaces/$WORKSPACE_ID/eventSchemaSets/$SCHEMASET_ID/getDefinition" \
    | jq -r '.definition.parts[]
             | select(.path | endswith("EventSchemaSetDefinition.json"))
             | .payload | @base64d'
}

require_schemaset () {
  if [ -z "$SCHEMASET_ID" ]; then
    echo "Error: --schemaset-id is required for '$COMMAND${1:+ $1}'." >&2; exit 2
  fi
}

case "$COMMAND" in
  create)
    ensure_definition
    if [ -n "$FOLDER_ID" ]; then
      endpoint="workspaces/$WORKSPACE_ID/items"; mode="create-folder"
    else
      endpoint="workspaces/$WORKSPACE_ID/eventSchemaSets"; mode="create-root"
    fi
    show POST "$endpoint"
    make_body "$mode"
    if [ -n "$DRY_RUN" ]; then
      echo "Dry run — not sending. Request body ($(wc -c < "$BODY_TMP") bytes):"
      jq '.' "$BODY_TMP"
      exit 0
    fi
    call_api post "$endpoint" "$BODY_TMP"
    ;;

  update)
    require_schemaset
    ensure_definition
    endpoint="workspaces/$WORKSPACE_ID/eventSchemaSets/$SCHEMASET_ID/updateDefinition"
    show POST "$endpoint"
    make_body update
    if [ -n "$DRY_RUN" ]; then
      echo "Dry run — not sending. Request body ($(wc -c < "$BODY_TMP") bytes):"
      jq '.' "$BODY_TMP"
      exit 0
    fi
    call_api post "$endpoint" "$BODY_TMP"
    ;;

  list)
    case "$LIST_TARGET" in
      schemasets)
        show GET "workspaces/$WORKSPACE_ID/eventSchemaSets"
        [ -n "$DRY_RUN" ] && exit 0
        resp="$(call_api get "workspaces/$WORKSPACE_ID/eventSchemaSets")"
        if [ "$(printf '%s' "$resp" | jq '.value | length')" -eq 0 ]; then
          echo "No event schema sets found in workspace $WORKSPACE_ID."
        else
          printf '%s' "$resp" | jq -r '.value[] | "\(.id)  \(.displayName)"'
        fi
        if printf '%s' "$resp" | jq -e 'has("continuationToken")' >/dev/null 2>&1; then
          echo "(more results available; this lists only the first page)" >&2
        fi
        ;;
      event-types)
        require_schemaset event-types
        show POST "workspaces/$WORKSPACE_ID/eventSchemaSets/$SCHEMASET_ID/getDefinition"
        [ -n "$DRY_RUN" ] && exit 0
        get_definition | jq -r '.eventTypes[].id'
        ;;
      schemas)
        require_schemaset schemas
        show POST "workspaces/$WORKSPACE_ID/eventSchemaSets/$SCHEMASET_ID/getDefinition"
        [ -n "$DRY_RUN" ] && exit 0
        get_definition | jq -r '.schemas[] | "\(.id)  (\(.versions | length) version(s))"'
        ;;
    esac
    ;;
esac
