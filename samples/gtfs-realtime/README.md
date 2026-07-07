# GTFS-Realtime — Event Schema Set sample

A real-world, multi-schema example of creating a Fabric **[Event Schema Set](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/schema-registry-overview)** and populating it with Avro schemas via the Fabric REST API.

> New here? Start with the [repository README](../../README.md) for prerequisites, the concept overview, and how the root launcher works.

**Source:** [GTFS-Realtime](https://gtfs.org/documentation/realtime/reference/) public-transit feed, as normalized by the [clemensv/real-time-sources GTFS feeder](https://github.com/clemensv/real-time-sources/tree/main/feeders/gtfs). The field-level contract is taken from that feeder's `xreg/gtfs.xreg.json` manifest.

> The upstream feeder ships **JsonStructure** schemas. Schema Registry is **Avro-only** today, so the schemas here are the same field contract rendered as Avro/1.12.0.

## What's in the set

| Event type (id) | Schema | Versions | What it carries |
|---|---|---|---|
| `GeneralTransitFeedRealTime.Vehicle.VehiclePosition` | `VehiclePositionEventData` | v1, v2 | Live vehicle location, occupancy, congestion |
| `GeneralTransitFeedRealTime.Trip.TripUpdate` | `TripUpdateEventData` | v1 | Per-stop arrival/departure predictions |
| `GeneralTransitFeedRealTime.Alert.Alert` | `AlertEventData` | v1 | Service alerts (cause, effect, affected entities) |

```
gtfs-realtime/
  schemas/                            # Avro schema sources (edit these)
    VehiclePositionEventData.avsc        # v1
    VehiclePositionEventData.v2.avsc     # v2 (adds occupancy_percentage, multi_carriage_details)
    TripUpdateEventData.avsc
    AlertEventData.avsc
  payload/                            # sample event payloads (plain JSON, as emitted on the wire)
    VehiclePosition-example.json         # v1
    VehiclePosition-v2-example.json      # v2
    TripUpdate-example.json
    Alert-example.json
  EventSchemaSetDefinition.json       # generated SchemaSet topology (schemas + eventTypes)
  create-schemaset.sh                 # assembles the definition and creates the set
```

## Create the schema set

**Prerequisites:** a Fabric workspace, `jq`, and `az` or `fab` signed in as a user — see the [repository README](../../README.md#prerequisites).

```bash
# From the repo root — the launcher runs this (default) sample
./create-schemaset.sh --workspace <workspace-guid>

# Preview the assembled definition and request, without creating anything
./create-schemaset.sh --dry-run

# Place the item inside a workspace folder, by name (resolved via the List Folders API)
./create-schemaset.sh --workspace <workspace-guid> --folder "Real-Time"

# ...or by folder id
./create-schemaset.sh --workspace <workspace-guid> --folder-id <folder-guid>

# Run this sample directly instead of via the root launcher
cd samples/gtfs-realtime
./create-schemaset.sh --workspace <workspace-guid>

# All options
./create-schemaset.sh --help
```

The script assembles `EventSchemaSetDefinition.json` from the `.avsc` files (using `jq` so the Avro never has to be hand-escaped), base64-encodes it into the item definition part, and creates the item via `az rest` or `fab api`.

**Folder placement:** the typed `POST .../eventSchemaSets` endpoint has no `folderId`. When `--folder`/`--folder-id` is set, the script instead calls the generic **Create Item** endpoint (`POST .../items` with `type: "EventSchemaSet"` + `folderId`), which does support it. `--folder` is resolved to an id by display name via **List Folders** — pass `--folder-id` directly if the folder name is nested or duplicated.

## Schema versioning

`VehiclePositionEventData` carries two versions in its `versions[]` array:

- **v1** — the base schema (`VehiclePositionEventData.avsc`).
- **v2** — (`VehiclePositionEventData.v2.avsc`) adds two optional fields: vehicle-level `occupancy_percentage` and per-carriage `multi_carriage_details` (both real GTFS-Realtime additions).

Schema Registry tracks versions as **incremental numbers** — each edit to a schema becomes a new version. It does **not** perform compatibility checks or automatic schema evolution today, so a change that removes or retypes fields can break downstream consumers. Because v2 here only **adds optional fields with defaults**, it's a safe, additive change (forward-compatible by Avro's own resolution rules) — the recommended way to evolve a schema. See [Update a schema](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/create-manage-event-schemas#update-an-event-schema).

To add another version, drop a new `.avsc` in `schemas/`, list it after the current one in `create-schemaset.sh`, and re-run.

## Notes

- **Sample payloads.** The `payload/` folder holds example events for each schema (including a v2 `VehiclePosition`), shown as plain JSON as they'd appear on the wire — handy for testing producers and consumers against the registered schemas.
- Each schema is paired 1:1 with an **event type** via `schemaUrl` (`#/schemas/{schemaId}`), which the current implementation requires.
- Creating an Event Schema Set supports **User** identity only today (no service principal).
- The generated `create-body.json` is workspace-specific and git-ignored.
