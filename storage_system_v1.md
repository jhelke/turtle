# Storage System v1

v1 storage is a physical, searchable taxonomy system.

Its job is:

```text
Put things where they belong and tell me what exists.
```

It does not fetch items, craft items, teach itself new items, or run machine
logistics.

## Components

`player dump chest`:
The player-facing input. Items placed here are candidates for intake.

`intake computer`:
Reads the dump chest, classifies item stacks against the `taxonomy_v1` routing
table, and moves known items to the correct taxonomy chest wall destination.

`taxonomy_v1 routing table`:
Maps item IDs to category paths. This table drives intake routing and should
match the physical labels from `storage_taxonomy_v1.md`.

`manual taxonomy chest wall`:
The physical storage backend and source of truth.

`index scanner`:
Scans taxonomy storage and produces searchable inventory visibility.

`item index`:
Records what exists, where it is, and how much exists.

## Intake Behavior

The intake system receives dumped items and attempts to classify each item
against the routing table.

Known items should move into their mapped taxonomy chest wall section.

Impossible routing cases should move to Overflow for v1. This includes items
without a route, unavailable destination storage, or cases where the intake
system cannot safely decide what to do.

## Index Behavior

The index scanner records:

- Item ID or item name.
- Count.
- Chest or inventory peripheral.
- Slot.
- Category path.

The index provides search and visibility only. It is the replacement for early
"Grid" visibility, not a retrieval system.

## Manual Chest Wall

The chest wall remains the physical source of truth. Its labels use the
`taxonomy_v1` category paths.

Manual correction is expected in v1. If the player fixes a category layout by
hand, the index should reflect that after the next scan.

## Explicit Non-Goals

The following are out of scope for v1:

- Unknown item review workflow.
- Assigning taxonomy paths from an in-game review UI.
- Automatically updating the routing table based on review decisions.
- Mekanism input/output logistics.
- Moving raw inputs into machines.
- Returning machine outputs to taxonomy storage.
- Automatic item retrieval from the chest wall.
- Autocrafting.
- Refined Storage as the main storage backend.

These are intentionally deferred so v1 stays focused on intake, physical
organization, and searchable visibility.
