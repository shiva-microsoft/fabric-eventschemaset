#!/usr/bin/env bash
# build-definition.sh — assemble a Fabric EventSchemaSetDefinition.json from a sample.
#
# Reads <sample>/manifest.json plus the Avro (.avsc) files it references and writes
# <sample>/EventSchemaSetDefinition.json — the item definition document: schemas[]
# (each with versioned, inlined Avro) and eventTypes[] that reference them.
#
# This is a local, offline transform — no sign-in required. It only needs jq, so
# the Avro never has to be hand-escaped. The sample-specific mapping lives in the
# sample's manifest.json (data), which is why this script stays generic.
#
# Usage:
#   build-definition.sh <sample-dir> [--out <file>]
#
# Example:
#   build-definition.sh samples/gtfs-realtime
#
# manifest.json shape:
#   {
#     "displayName": "...", "description": "...",
#     "schemas":   [ { "id": "Foo", "versions": ["schemas/Foo.avsc", "schemas/Foo.v2.avsc"] } ],
#     "eventTypes":[ { "id": "com.example.Foo", "schema": "Foo" } ]
#   }
# A version entry may also be an object: { "file": "...", "id": "v1", "format": "Avro/1.12.0" }.
set -euo pipefail

SCHEMA_FORMAT_DEFAULT="Avro/1.12.0"
EVENTTYPE_FORMAT_DEFAULT="CloudEvents/1.0"

usage () {
  cat <<'EOF'
Assemble a Fabric EventSchemaSetDefinition.json from a sample's manifest + .avsc files.

Usage:
  build-definition.sh <sample-dir> [--out <file>]

Arguments:
  <sample-dir>          Sample folder containing manifest.json and schemas/*.avsc.

Options:
  -o, --out <file>      Output path (default: <sample-dir>/EventSchemaSetDefinition.json).
  -h, --help            Show this help and exit.

Example:
  build-definition.sh samples/gtfs-realtime
EOF
}

SAMPLE_DIR=""
OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--out)  OUT="${2:?--out requires a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*)        echo "Unknown option: $1" >&2; echo >&2; usage >&2; exit 2 ;;
    *)         if [ -z "$SAMPLE_DIR" ]; then SAMPLE_DIR="$1"; shift
               else echo "Unexpected argument: $1" >&2; exit 2; fi ;;
  esac
done

if [ -z "$SAMPLE_DIR" ]; then
  echo "Error: a sample directory is required." >&2
  echo >&2
  usage >&2
  exit 2
fi
command -v jq >/dev/null 2>&1 || { echo "Error: jq is required." >&2; exit 1; }

SAMPLE_DIR="${SAMPLE_DIR%/}"
MANIFEST="$SAMPLE_DIR/manifest.json"
[ -f "$MANIFEST" ] || { echo "Error: no manifest.json in '$SAMPLE_DIR'." >&2; exit 1; }
jq empty "$MANIFEST" 2>/dev/null || { echo "Error: $MANIFEST is not valid JSON." >&2; exit 1; }
OUT="${OUT:-$SAMPLE_DIR/EventSchemaSetDefinition.json}"

# --- schemas[] : inline each version's Avro as a stringified schema -----------
schemas_json="[]"
schema_count="$(jq '.schemas | length' "$MANIFEST")"
for (( si = 0; si < schema_count; si++ )); do
  sid="$(jq -r --argjson i "$si" '.schemas[$i].id' "$MANIFEST")"
  sfmt="$(jq -r --argjson i "$si" --arg d "$SCHEMA_FORMAT_DEFAULT" '.schemas[$i].format // $d' "$MANIFEST")"
  vcount="$(jq --argjson i "$si" '.schemas[$i].versions | length' "$MANIFEST")"
  if [ "$vcount" -eq 0 ]; then
    echo "Error: schema '$sid' has no versions." >&2; exit 1
  fi

  versions="[]"
  for (( vi = 0; vi < vcount; vi++ )); do
    if [ "$(jq -r --argjson i "$si" --argjson j "$vi" '.schemas[$i].versions[$j] | type' "$MANIFEST")" = "string" ]; then
      vfile="$(jq -r --argjson i "$si" --argjson j "$vi" '.schemas[$i].versions[$j]' "$MANIFEST")"
      vid="v$(( vi + 1 ))"
      vfmt="$sfmt"
    else
      vfile="$(jq -r --argjson i "$si" --argjson j "$vi" '.schemas[$i].versions[$j].file' "$MANIFEST")"
      vid="$(jq -r --argjson i "$si" --argjson j "$vi" --arg d "v$(( vi + 1 ))" '.schemas[$i].versions[$j].id // $d' "$MANIFEST")"
      vfmt="$(jq -r --argjson i "$si" --argjson j "$vi" --arg d "$sfmt" '.schemas[$i].versions[$j].format // $d' "$MANIFEST")"
    fi

    avsc="$SAMPLE_DIR/$vfile"
    [ -f "$avsc" ] || { echo "Error: schema file not found: $avsc" >&2; exit 1; }
    jq empty "$avsc" 2>/dev/null || { echo "Error: $avsc is not valid JSON." >&2; exit 1; }

    versions="$(jq -n --argjson acc "$versions" --arg vid "$vid" --arg fmt "$vfmt" --rawfile avro "$avsc" \
      '$acc + [ { id: $vid, format: $fmt, schema: ($avro | fromjson | tojson) } ]')"
  done

  schemas_json="$(jq -n --argjson acc "$schemas_json" --arg id "$sid" --arg fmt "$sfmt" --argjson versions "$versions" \
    '$acc + [ { id: $id, format: $fmt, versions: $versions } ]')"
done

# --- eventTypes[] : one CloudEvents type per entry, referencing a schema ------
et_json="[]"
et_count="$(jq '.eventTypes | length' "$MANIFEST")"
for (( ei = 0; ei < et_count; ei++ )); do
  eid="$(jq -r --argjson i "$ei" '.eventTypes[$i].id' "$MANIFEST")"
  esid="$(jq -r --argjson i "$ei" '.eventTypes[$i].schema' "$MANIFEST")"
  efmt="$(jq -r --argjson i "$ei" --arg d "$EVENTTYPE_FORMAT_DEFAULT" '.eventTypes[$i].format // $d' "$MANIFEST")"
  esfmt="$(jq -r --argjson i "$ei" --arg d "$SCHEMA_FORMAT_DEFAULT" '.eventTypes[$i].schemaFormat // $d' "$MANIFEST")"

  if ! jq -e --arg s "$esid" '.schemas[] | select(.id == $s)' "$MANIFEST" >/dev/null; then
    echo "Error: event type '$eid' references unknown schema '$esid'." >&2; exit 1
  fi

  et_json="$(jq -n --argjson acc "$et_json" --arg id "$eid" --arg sid "$esid" --arg fmt "$efmt" --arg sfmt "$esfmt" \
    '$acc + [ { id: $id, format: $fmt, schemaUrl: ("#/schemas/" + $sid), schemaFormat: $sfmt } ]')"
done

jq -n --argjson ets "$et_json" --argjson schemas "$schemas_json" \
  '{ eventTypes: $ets, schemas: $schemas }' > "$OUT"

echo "Wrote $OUT ($(wc -c < "$OUT") bytes): $schema_count schema(s), $et_count event type(s)."
