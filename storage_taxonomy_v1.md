# Storage Taxonomy v1

`taxonomy_v1` is the base physical storage taxonomy for the manual chest wall
and intake routing table.

## Label Style

Use readable category paths on chest labels and route-table entries.

```text
Category - Subcategory
Category - Subcategory, Sibling
Category - Subcategory - Detail
```

Examples:

```text
Stone - Deepslate
Metals - Raw
Machine Parts - Mekanism
Unknown - Review
```

## Categories

```text
Wood
Stone
Dirt/Sand/Gravel
Glass/Clay

Metals
Gems
Dusts
Machine Parts

Food
Farming
Mob Drops
Nature

Magic
Exploration
Building Decor
Tools/Gear

Unknown
Overflow
Temporary Projects
Trash/Recycle
```

## Special Categories

`Unknown`:
Reserved for items the system cannot classify yet. In v1, unknown handling is
manual or routed to Overflow. A formal Unknown review workflow is v2 scope.

`Overflow`:
Receives items that cannot be routed into the expected taxonomy destination.
This can include full destination chests, missing route definitions, or other
impossible cases.

`Temporary Projects`:
Temporary project storage. This is not a permanent taxonomy destination unless
the player deliberately keeps an item there.

`Trash/Recycle`:
Items that are intentionally disposable or recyclable. Intake code should be
conservative before moving items here.
