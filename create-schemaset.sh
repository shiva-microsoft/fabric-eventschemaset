#!/usr/bin/env bash
# Root launcher for the fabric-eventschemaset samples.
#
# Creates a Microsoft Fabric Event Schema Set from one of the samples in this repo.
# Selects a sample (default: gtfs-realtime) and forwards the remaining options to
# that sample's own create-schemaset.sh.
#
# Docs: https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/schema-registry-overview
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLES_DIR="$SCRIPT_DIR/samples"
SAMPLE="gtfs-realtime"

list_samples () {
  echo "Available samples:"
  for d in "$SAMPLES_DIR"/*/create-schemaset.sh; do
    [ -e "$d" ] && echo "  - $(basename "$(dirname "$d")")"
  done
}

usage () {
  cat <<EOF
Create a Microsoft Fabric Event Schema Set from one of the samples in this repo.

Usage:
  create-schemaset.sh [--sample <name>] [sample options...]

Launcher options:
  -s, --sample <name>   Which sample to run (default: $SAMPLE).
      --list-samples    List available samples and exit.
  -h, --help            Show this help and exit.

Any other options are forwarded to the selected sample's create-schemaset.sh.
Commonly:
  -w, --workspace <guid>   Target Fabric workspace ID (required to create).
      --dry-run            Assemble the definition and show the request, but don't create.
  -f, --folder <name>      Place the item in a workspace folder.

Examples:
  create-schemaset.sh --workspace 1111-2222-3333
  create-schemaset.sh --dry-run
  create-schemaset.sh --sample gtfs-realtime --workspace 1111-2222-3333 --folder "Real-Time"

$(list_samples)

For sample-specific options, see the sample's README or run:
  bash samples/<sample>/create-schemaset.sh --help
EOF
}

# Peel off launcher-level options; forward everything else to the sample script.
forward=()
while [ $# -gt 0 ]; do
  case "$1" in
    -s|--sample)     SAMPLE="${2:?--sample requires a value}"; shift 2 ;;
    --list-samples)  list_samples; exit 0 ;;
    -h|--help)       usage; exit 0 ;;
    *)               forward+=("$1"); shift ;;
  esac
done

TARGET="$SAMPLES_DIR/$SAMPLE/create-schemaset.sh"
if [ ! -f "$TARGET" ]; then
  echo "Error: unknown sample '$SAMPLE' (no samples/$SAMPLE/create-schemaset.sh)." >&2
  echo >&2
  list_samples >&2
  exit 1
fi

exec bash "$TARGET" ${forward+"${forward[@]}"}
