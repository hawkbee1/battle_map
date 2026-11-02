# Benchmark results

## Memory of one loaded 10 × 50 km map (M5 Issue 8)

`dart run battle_map:map_memory_bench ../../apps/battle_team/plan --tiles`, Dart VM on
Linux x64 in the hawkbee dev container, 2026-11-02. A synthetic map of 1,000 × 5,000
cells of 10 m with 187,960 objects (150,000 trees, 37,960 buildings), loaded by
`HostMapLoader`. Memory is the growth of the process's resident set, an upper bound:
it includes garbage the VM has not collected yet.

| Measure | Result | Stack decision 1 estimate |
|---|---|---|
| Ground (`NavigationMap` cells) | 40 MB | about 20 MB |
| Objects (navigation sets and `MapObject`s) | 111 MB | about 15 MB |
| Whole loaded map | 152 MB | about 35 MB |
| `make` from decoded layers | 0.4 s | |
| Writing the 80 tiles | 0.8 s | |
| Loading the 80 tiles (PNG decoding included) | 1.8 s | |

Why it is above the estimate:
- **Ground**: `NavigationMap.ground` is a `List<NavCell>`. The loader shares equal cells,
  so the cell objects are few, but the list keeps one 8-byte pointer per cell
  (5 million cells: 40 MB). Packed heights and terrain indices (2 + 1 bytes per cell)
  would give 15 MB.
- **Objects**: about 590 bytes each. `NavigationMap.objects` is a
  `Map<CellRef, Set<String>>`, one map entry, one `CellRef` and one `Set` per occupied
  cell, copied once by its unmodifiable view; each `MapObject` adds its id and cell list.

Both are in `battle_pathfinding`'s model (M3 Issue 2), which this package builds and does
not copy. A packed model is a change to that package, to plan before P-02 counts the
battles one process holds.
