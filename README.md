# Microsoft Fabric — Event Schema Set samples

Ready-to-run samples that create an **Event Schema Set** in the [**Schema Registry**](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/schema-registry-overview)
of **Microsoft Fabric Real-Time Intelligence** — programmatically, from the command line.

Each sample takes a set of Avro schema files and creates a fully-populated Event Schema Set
in a Fabric workspace using the Fabric REST API (via the Azure CLI or the Fabric CLI). Use them
as a starting point for scripting, CI/CD, or bulk schema registration.

> **Preview.** Schema Registry in Fabric Real-Time Intelligence is currently in preview. Check
> [region availability](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/schema-registry-region-availability)
> before you start.

---

## What is Schema Registry?

Schema Registry is a central place to **define, validate, and evolve** the data schemas that flow
through your real-time pipelines. When a schema is registered, Fabric can check that events match it
as they move through an eventstream, during transformation, and before they reach destinations such
as Eventhouse, Lakehouse, or Activator — catching bad data early and keeping downstream consumers
consistent.

For the full concept overview, see
[Schema Registry in Fabric Real-Time Intelligence](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/schema-registry-overview).

### Key concepts

| Concept | What it is | Learn more |
|---|---|---|
| **Event Schema Set** | A Fabric workspace item that groups one or more related schemas for logical organization and centralized access control. | [Create and manage event schema sets](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/create-manage-event-schema-sets) |
| **Schema** | The data contract for an event — its fields and their types. Schema Registry supports the **Avro** format. | [Create and manage event schemas](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/create-manage-event-schemas) |
| **Version** | Every edit to a schema creates a new, incrementally numbered version. Fabric does **not** perform compatibility checks today, so prefer *adding* a new schema/version over changing an existing one. | [Update a schema](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/create-manage-event-schemas#update-an-event-schema) |
| **Event type** | In the item definition used by these samples, each schema is paired with an event type that carries the [CloudEvents](https://cloudevents.io/) `type` and points at the schema. | — |

---

## Samples

| Sample | What it creates | Highlights |
|---|---|---|
| [`gtfs-realtime/`](gtfs-realtime/README.md) | A public-transit schema set from the [GTFS-Realtime](https://gtfs.org/documentation/realtime/reference/) feed: `VehiclePosition`, `TripUpdate`, `Alert`. | Multiple schemas in one set; a schema with **two versions** (v1 → v2 adds optional fields). |

---

## Prerequisites

- A **Microsoft Fabric workspace** on a supported Fabric capacity, in a region where
  [Schema Registry is available](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/schema-registry-region-availability).
- One of the following CLIs, signed in **as a user** (creating an Event Schema Set supports user
  identity only today — no service principal):
  - [**Azure CLI**](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az`), or
  - [**Fabric CLI**](https://learn.microsoft.com/rest/api/fabric/articles/fabric-command-line-interface) (`fab`).
- [`jq`](https://jqlang.github.io/jq/) — used to assemble the schema-set definition from the `.avsc` files.
- `bash`, `base64` (standard on macOS/Linux; on Windows use WSL or Git Bash).

Find your **workspace ID** in the Fabric portal URL when the workspace is open:
`https://app.fabric.microsoft.com/groups/<workspace-id>/...`.

---

## Quick start

Run from the repository root:

```bash
# Sign in first (user identity)
az login            # or: fab auth login

# Create the default sample (gtfs-realtime) in your workspace
./create-schemaset.sh --workspace <workspace-guid>

# Preview what would be sent, without creating anything
./create-schemaset.sh --dry-run

# Place the item inside a workspace folder
./create-schemaset.sh --workspace <workspace-guid> --folder "Real-Time"

# Pick a specific sample / list what's available
./create-schemaset.sh --sample gtfs-realtime --workspace <workspace-guid>
./create-schemaset.sh --list-samples

# Full option list
./create-schemaset.sh --help
```

`create-schemaset.sh` at the root is a thin launcher: it selects a sample (default `gtfs-realtime`)
and forwards the remaining options to that sample's own `create-schemaset.sh`. You can also run a
sample directly, e.g. `bash gtfs-realtime/create-schemaset.sh --help`.

---

## How it works

1. The sample's script assembles `EventSchemaSetDefinition.json` from the `.avsc` files with `jq`,
   so the Avro never has to be hand-escaped.
2. It base64-encodes that definition into a Fabric item **definition part** and `POST`s it to the
   Fabric REST API (`.../workspaces/{id}/eventSchemaSets`, or the generic Create Item endpoint when
   targeting a folder) via `az rest` or `fab api`.
3. The result is an Event Schema Set item in your workspace, pre-populated with all schemas, versions,
   and event types.

See [`gtfs-realtime/README.md`](gtfs-realtime/README.md) for a step-by-step walkthrough of one sample,
including the schema/version layout and sample event payloads.

### Prefer the portal?

You can also create schema sets and schemas interactively in the Fabric UI (upload a file, paste JSON,
or build field-by-field). See
[Create and manage event schema sets](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/create-manage-event-schema-sets)
and [Create and manage event schemas](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/create-manage-event-schemas).

---

## Learn more

- [Schema Registry overview](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/schema-registry-overview)
- [Create and manage event schema sets](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/create-manage-event-schema-sets)
- [Create and manage event schemas](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/create-manage-event-schemas)
- [Schema Registry region availability](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/schema-sets/schema-registry-region-availability)
- [Fabric REST API reference](https://learn.microsoft.com/rest/api/fabric/articles/using-fabric-apis)
