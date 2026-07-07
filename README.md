# Microsoft Fabric — Event Schema Set samples

This repository contains samples for creating an **Event Schema Set** in the [**Event Schema Registry**](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/schema-registry-overview)
so that they can be used with **Microsoft Fabric Eventstreams** — programmatically, from the command line.

Each sample takes a set of Avro schema files and creates a fully-populated Event Schema Set
in a Fabric workspace using the Fabric REST API (called with `curl`, authenticated via the Azure CLI).
Use them as a starting point for scripting, CI/CD, or bulk schema registration.

> **Preview.** Schema Registry in Fabric Real-Time Intelligence is currently in preview. Check
> [region availability](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/schema-registry-region-availability)
> before you start.

---

## Event Schema Registry and Event Schema Sets

Schema Registry is a central place to **define, validate, and evolve** the data schemas that flow
through your real-time pipelines. When a schema is registered, and then used to configure an Eventstream connector, messages that pass through that connector are mapped to the schemas using the rules you configure, and then any messages that do not conform to the schema are rejected. This ensures that messages delivered into your eventstream are valid and consistent, and that downstream consumers can rely on the schema to interpret the data correctly. You can avoid errors during transformation, and destination such as Eventhouse, Lakehouse, or Activator — catching bad data early and keeping downstream consumers consistent.

For the full concept overview, see
[Schema Registry in Fabric Real-Time Intelligence](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/schema-registry-overview).

An **Event Schema Set** is the top-level workspace item you create in Fabric. It groups related event schemas and their event types so producers and consumers can share one governed contract in Eventstreams.

### Key concepts

| Concept | What it is | Learn more |
|---|---|---|
| **Event Schema Set** | A Fabric workspace item that groups one or more related schemas for logical organization and centralized access control. | [Create and manage event schema sets](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/create-manage-event-schema-sets) |
| **Schema** | The data contract for an event — its fields and their types. Schema Registry supports the **Avro** format. | [Create and manage event schemas](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/create-manage-event-schemas) |
| **Version** | Every edit to a schema creates a new, incrementally numbered version. Fabric does **not** perform compatibility checks today, so prefer *adding* a new schema/version over changing an existing one. | [Update a schema](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/create-manage-event-schemas#update-an-event-schema) |
| **Event type** | In the item definition used by these samples, each schema is paired with an event type that carries the [CloudEvents](https://cloudevents.io/) `type` and points at the schema. | — |

---

## xRegistry Support and Fabric Terminology

Fabric Event Schema Registry supports the [xRegistry](https://github.com/xregistry/spec) model, and these samples follow that shape when building an item definition.

The table below shows how common xRegistry concepts map to Fabric terms used in this repo:

| xRegistry concept | Fabric term | How it appears in these samples |
|---|---|---|
| **registry** | **Event Schema Registry** | The Fabric registry capability in your workspace/capacity. |
| **schema group / collection** | **Event Schema Set** | One Fabric item containing related schemas + event types. |
| **schema** | **Schema** | Avro schema entry under `schemas[]`. |
| **schema version** | **Version** | Ordered entries under a schema's `versions[]`. |
| **message/event type** | **Event type** | CloudEvents `type` mapped to a schema via `schemaUrl`. |

In these samples, each event type is associated with one schema reference (`#/schemas/{schemaId}`) inside the Event Schema Set definition document.

---

## Samples

| Sample | What it creates | Highlights |
|---|---|---|
| [`samples/gtfs-realtime/`](samples/gtfs-realtime/) | A public-transit schema set from the [GTFS-Realtime](https://gtfs.org/documentation/realtime/reference/) feed: `VehiclePosition`, `TripUpdate`, `Alert`. See [details below](#the-gtfs-realtime-sample). | Multiple schemas in one set; a schema with **two versions** (v1 → v2 adds optional fields). |

---

## Prerequisites

- A **Microsoft Fabric workspace** on a supported Fabric capacity, in a region where
  [Schema Registry is available](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/schema-registry-region-availability).
- One of the following, signed in **as a user** (creating an Event Schema Set supports user
  identity only today — no service principal):
  - the [**Azure CLI**](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az login`).
- [`curl`](https://curl.se/) — used to make the Fabric REST calls (the bearer token comes from `az`).
- [`jq`](https://jqlang.github.io/jq/) — used to assemble the schema-set definition from the `.avsc` files.
- `bash`, `base64` (standard on macOS/Linux; on Windows use WSL or Git Bash).

Find your **workspace ID** in the Fabric portal URL when the workspace is open:
`https://app.fabric.microsoft.com/groups/<workspace-id>/...`.

---

## Quick start

Run from the repository root. Building a definition is offline; creating, updating, and listing need sign-in.

```bash
# 1) Sign in (User identity — no service principal today)
az login

# 2) Build the sample's definition from its .avsc files (offline, no sign-in)
./build-definition.sh samples/gtfs-realtime

# 3) Create the schema set in your workspace
#    (add --folder-id <guid> to place it inside a workspace folder)
./schemaset.sh create --workspace <workspace-guid> --sample samples/gtfs-realtime

# 4) List the Event Schema Sets in the workspace (grab the new one's id)
./schemaset.sh list schemasets --workspace <workspace-guid>

# 5) Inspect what was created
./schemaset.sh list event-types --workspace <workspace-guid> --schemaset-id <schemaset-guid>
./schemaset.sh list schemas     --workspace <workspace-guid> --schemaset-id <schemaset-guid>

# 6) Edit the sample and push the change as a new definition
./schemaset.sh update --workspace <workspace-guid> --schemaset-id <schemaset-guid> --sample samples/gtfs-realtime
```

`create`/`update` rebuild the definition first (pass `--no-build` to skip), and any command accepts
`--dry-run` to print the REST call — and request body — without sending it. Run `./schemaset.sh --help`
for the full option list.

---

## How it works

Two small, generic scripts at the repo root drive every sample; the sample folders hold **data only**.

1. [`build-definition.sh`](build-definition.sh) reads a sample's `manifest.json` — which `.avsc`
   files map to which schema/version, plus the event types — and assembles
   `EventSchemaSetDefinition.json` with `jq`, so the Avro is never hand-escaped. Adding a sample
   means adding data (schemas + a manifest), not code.
2. [`schemaset.sh`](schemaset.sh) base64-encodes that definition into a Fabric item **definition
   part** and calls the Fabric REST API with `curl` (using a bearer token from `az account get-access-token`):
   - **create** → `POST .../eventSchemaSets` (workspace root), or `POST .../items` with `folderId` (into a folder)
   - **update** → `POST .../eventSchemaSets/{id}/updateDefinition`
   - **list** → `GET .../eventSchemaSets`, or `POST .../eventSchemaSets/{id}/getDefinition` to read the event types / schemas inside a set

The result is an Event Schema Set item in your workspace, pre-populated with all schemas, versions,
and event types.

See [The gtfs-realtime sample](#the-gtfs-realtime-sample) below for the schema and version layout, and
the example event payloads under [`samples/gtfs-realtime/payload/`](samples/gtfs-realtime/payload/).

### Prefer the portal?

You can also create schema sets and schemas interactively in the Fabric UI (upload a file, paste JSON,
or build field-by-field). See
[Create and manage event schema sets](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/create-manage-event-schema-sets)
and [Create and manage event schemas](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/create-manage-event-schemas).

---

## The gtfs-realtime sample

The included sample builds a public-transit schema set from the [GTFS-Realtime](https://gtfs.org/documentation/realtime/reference/) feed, as normalized by the [clemensv/real-time-sources GTFS feeder](https://github.com/clemensv/real-time-sources/tree/main/feeders/gtfs) (field contract from that feeder's `xreg/gtfs.xreg.json`). The upstream feeder ships **JsonStructure** schemas; Schema Registry is **Avro-only** today, so the same field contract is rendered here as Avro/1.12.0.

### What's in the set

| Event type (id) | Schema | Versions | What it carries |
|---|---|---|---|
| `GeneralTransitFeedRealTime.Vehicle.VehiclePosition` | `VehiclePositionEventData` | v1, v2 | Live vehicle location, occupancy, congestion |
| `GeneralTransitFeedRealTime.Trip.TripUpdate` | `TripUpdateEventData` | v1 | Per-stop arrival/departure predictions |
| `GeneralTransitFeedRealTime.Alert.Alert` | `AlertEventData` | v1 | Service alerts (cause, effect, affected entities) |

### Layout

```
samples/gtfs-realtime/
  manifest.json                    # schemas (+ ordered version files) and event types
  schemas/*.avsc                   # Avro schema sources (edit these)
  payload/*.json                   # example event payloads, as they'd appear on the wire
  EventSchemaSetDefinition.json    # generated by build-definition.sh (do not hand-edit)
```

### Schema versioning

`VehiclePositionEventData` carries two versions: **v1** (`VehiclePositionEventData.avsc`) and **v2** (`VehiclePositionEventData.v2.avsc`, which adds optional `occupancy_percentage` and per-carriage `multi_carriage_details`). Fabric tracks versions as **incremental numbers** and does **not** run compatibility checks today, so a change that removes or retypes fields can break consumers. Because v2 only **adds optional fields with defaults**, it's a safe, additive change (forward-compatible by Avro's own resolution rules).

To add another version: drop the new `.avsc` in `samples/gtfs-realtime/schemas/`, append it to that schema's `versions` array in `samples/gtfs-realtime/manifest.json`, then re-run `build-definition.sh` and `schemaset.sh update`. Each schema is paired 1:1 with an event type via `schemaUrl` (`#/schemas/{schemaId}`), which the current implementation requires.

---

## Learn more

- [Schema Registry overview](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/schema-registry-overview)
- [Create and manage event schema sets](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/create-manage-event-schema-sets)
- [Create and manage event schemas](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/create-manage-event-schemas)
- [Schema Registry region availability](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/schema-registry-region-availability)
- [Fabric REST API reference](https://learn.microsoft.com/rest/api/fabric/articles/using-fabric-apis)
