#!/usr/bin/env bash
# Create the GTFS-Realtime Event SchemaSet in a Microsoft Fabric workspace.
#
# Builds the Event SchemaSet definition from the .avsc files in schemas/ (three
# event types: VehiclePosition, TripUpdate, Alert) and creates the SchemaSet.
# Field contract mirrors the clemensv/real-time-sources GTFS feeder (xreg/gtfs.xreg.json).
#
# Prereqs: jq, and either the Azure CLI (az) or the Fabric CLI (fab), authenticated.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

usage () {
  cat <<'EOF'
Create the GTFS-Realtime Event SchemaSet in a Microsoft Fabric workspace.

Usage:
  create-schemaset.sh --workspace <guid> [options]

Required:
  -w, --workspace <guid>      Fabric workspace ID (not required with --dry-run).

Options:
  -f, --folder <name>         Target folder by display name (resolved via List Folders).
      --folder-id <guid>      Target folder by ID (takes precedence over --folder).
  -n, --display-name <name>   Item display name (default: "GTFS Realtime Schemas").
  -d, --description <text>    Item description.
      --dry-run               Assemble the definition and request body, print them, and
                              exit without creating anything (no sign-in required).
  -h, --help                  Show this help and exit.

Folder note: the typed .../eventSchemaSets endpoint has no folderId, so when a folder
is given the item is created via the generic Create Item endpoint
(POST .../items with type=EventSchemaSet + folderId).

Examples:
  create-schemaset.sh -w 1111-2222-3333
  create-schemaset.sh --dry-run
  create-schemaset.sh -w 1111-2222-3333 --folder "Real-Time"
  create-schemaset.sh -w 1111-2222-3333 --folder-id 4444-5555 -n "GTFS Transit Schemas"
EOF
}

# Defaults (overridden by flags).
WORKSPACE_ID=""
FOLDER=""
FOLDER_ID=""
DISPLAY_NAME="GTFS Realtime Schemas"
DESCRIPTION="GTFS-Realtime transit event schemas: VehiclePosition, TripUpdate, Alert"
DRY_RUN=""

# Parse arguments.
while [ $# -gt 0 ]; do
  case "$1" in
    -w|--workspace)     WORKSPACE_ID="${2:?--workspace requires a value}"; shift 2 ;;
    -f|--folder)        FOLDER="${2:?--folder requires a value}"; shift 2 ;;
    --folder-id)        FOLDER_ID="${2:?--folder-id requires a value}"; shift 2 ;;
    -n|--display-name)  DISPLAY_NAME="${2:?--display-name requires a value}"; shift 2 ;;
    -d|--description)   DESCRIPTION="${2:?--description requires a value}"; shift 2 ;;
    --dry-run)          DRY_RUN=1; shift ;;
    -h|--help)          usage; exit 0 ;;
    --)                 shift; break ;;
    -*)                 echo "Unknown option: $1" >&2; echo >&2; usage >&2; exit 2 ;;
    *)                  echo "Unexpected argument: $1" >&2; echo >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$WORKSPACE_ID" ] && [ -z "$DRY_RUN" ]; then
  echo "Error: --workspace is required (or use --dry-run to preview)." >&2
  echo >&2
  usage >&2
  exit 2
fi

# call_api METHOD ENDPOINT [BODY_FILE] — authenticated Fabric REST call via az or fab.
# ENDPOINT is relative to https://api.fabric.microsoft.com/v1/. Prints the response body.
call_api () {
  local method="$1" endpoint="$2" body="${3:-}"
  if command -v az >/dev/null 2>&1; then
    local a=(--method "$method" --resource "https://api.fabric.microsoft.com"
             --url "https://api.fabric.microsoft.com/v1/$endpoint")
    if [ "$method" != get ]; then a+=(--headers "Content-Type=application/json"); fi
    if [ -n "$body" ]; then a+=(--body "@$body"); fi
    az rest "${a[@]}"
  elif command -v fab >/dev/null 2>&1; then
    local a=("$endpoint" -X "$method")
    if [ -n "$body" ]; then a+=(-H "content-type=application/json" -i "$body"); fi
    fab api "${a[@]}"
  else
    echo "Neither az nor fab found. Install one and re-run." >&2
    exit 1
  fi
}

# 1. Assemble EventSchemaSetDefinition.json from the .avsc sources.
#    schema_obj stringifies each Avro doc into a versions[] entry (no manual
#    escaping) — pass one .avsc per version in ascending order (v1, v2, ...).
#    Each schema is paired 1:1 with an event type; the event type's schemaUrl
#    points at the schema, which resolves to its latest version.
schema_obj () {  # $1 = schema id; $2.. = .avsc files in version order
  local sid="$1"; shift
  local versions="[]" i=0 f
  for f in "$@"; do
    i=$((i + 1))
    versions=$(jq -n --argjson acc "$versions" --arg vid "v$i" --rawfile avro "$f" \
      '$acc + [ { id: $vid, format: "Avro/1.12.0", schema: ($avro | fromjson | tojson) } ]')
  done
  jq -n --arg sid "$sid" --argjson versions "$versions" \
    '{ id: $sid, format: "Avro/1.12.0", versions: $versions }'
}

event_type () {  # $1 = event type id; $2 = schema id
  jq -n --arg id "$1" --arg sid "$2" \
    '{ id: $id, format: "CloudEvents/1.0", schemaUrl: ("#/schemas/" + $sid), schemaFormat: "Avro/1.12.0" }'
}

jq -n \
  --argjson vp "$(schema_obj VehiclePositionEventData schemas/VehiclePositionEventData.avsc schemas/VehiclePositionEventData.v2.avsc)" \
  --argjson tu "$(schema_obj TripUpdateEventData schemas/TripUpdateEventData.avsc)" \
  --argjson al "$(schema_obj AlertEventData schemas/AlertEventData.avsc)" \
  --argjson etvp "$(event_type GeneralTransitFeedRealTime.Vehicle.VehiclePosition VehiclePositionEventData)" \
  --argjson ettu "$(event_type GeneralTransitFeedRealTime.Trip.TripUpdate TripUpdateEventData)" \
  --argjson etal "$(event_type GeneralTransitFeedRealTime.Alert.Alert AlertEventData)" \
  '{ eventTypes: [ $etvp, $ettu, $etal ], schemas: [ $vp, $tu, $al ] }' \
  > EventSchemaSetDefinition.json

echo "Wrote EventSchemaSetDefinition.json ($(wc -c < EventSchemaSetDefinition.json) bytes)"

# 2. Resolve the target folder, if one was requested (optional).
#    FOLDER_ID wins; otherwise FOLDER (a display name) is looked up via List Folders.
if [ -z "$FOLDER_ID" ] && [ -n "$FOLDER" ]; then
  if [ -n "$DRY_RUN" ]; then
    echo "Dry run: skipping folder name resolution for \"$FOLDER\" (needs sign-in)."
    echo "         Pass --folder-id to preview the folder placement."
  else
    echo "Resolving folder \"$FOLDER\"..."
    FOLDER_ID="$(call_api get "workspaces/$WORKSPACE_ID/folders" \
      | jq -r --arg n "$FOLDER" '[.value[] | select(.displayName == $n)] as $m
          | if   ($m | length) == 1 then $m[0].id
            elif ($m | length) == 0 then "NOT_FOUND"
            else "AMBIGUOUS" end')"
    case "$FOLDER_ID" in
      NOT_FOUND) echo "No folder named \"$FOLDER\" in this workspace." >&2; exit 1 ;;
      AMBIGUOUS) echo "Multiple folders named \"$FOLDER\"; set FOLDER_ID to disambiguate." >&2; exit 1 ;;
    esac
    echo "  -> folderId $FOLDER_ID"
  fi
fi

# 3. Build the Create request body (base64 InlineBase64 part) and pick the endpoint.
PAYLOAD="$(base64 -w0 EventSchemaSetDefinition.json 2>/dev/null || base64 EventSchemaSetDefinition.json | tr -d '\n')"
if [ -n "$FOLDER_ID" ]; then
  # Target a folder via the generic Create Item endpoint (the only create path with folderId).
  jq -n --arg name "$DISPLAY_NAME" --arg desc "$DESCRIPTION" --arg fid "$FOLDER_ID" --arg payload "$PAYLOAD" \
    '{ displayName: $name, type: "EventSchemaSet", description: $desc, folderId: $fid,
       definition: { parts: [ { path: "EventSchemaSetDefinition.json", payload: $payload, payloadType: "InlineBase64" } ] } }' \
    > create-body.json
  CREATE_ENDPOINT="workspaces/${WORKSPACE_ID:-<workspace-guid>}/items"
else
  # Workspace root — use the typed EventSchemaSet endpoint.
  jq -n --arg name "$DISPLAY_NAME" --arg desc "$DESCRIPTION" --arg payload "$PAYLOAD" \
    '{ displayName: $name, description: $desc,
       definition: { parts: [ { path: "EventSchemaSetDefinition.json", payload: $payload, payloadType: "InlineBase64" } ] } }' \
    > create-body.json
  CREATE_ENDPOINT="workspaces/${WORKSPACE_ID:-<workspace-guid>}/eventSchemaSets"
fi
echo "Wrote create-body.json (POST $CREATE_ENDPOINT)"

# 4. Create the Event SchemaSet (User identity required today; SPN not supported).
if [ -n "$DRY_RUN" ]; then
  echo
  echo "Dry run - nothing was created. Would POST to:"
  echo "  https://api.fabric.microsoft.com/v1/$CREATE_ENDPOINT"
  echo "  definition:   EventSchemaSetDefinition.json ($(wc -c < EventSchemaSetDefinition.json) bytes)"
  echo "  request body: create-body.json ($(wc -c < create-body.json) bytes)"
  echo "Re-run with --workspace <guid> (after 'az login' or 'fab auth login') to create it."
  exit 0
fi
call_api post "$CREATE_ENDPOINT" create-body.json
