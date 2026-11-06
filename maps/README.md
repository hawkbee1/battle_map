# Maps

Battle Team maps made from real data (stack decision 5, authoring). Each map has:

- `source/<map>/import.yaml`: the area, the rules that turn OpenStreetMap elements into
  terrain and objects, and the starting points placed by hand;
- `built/<map>/`: the tiles the builder wrote, as the host reads them
  (`DirectoryMapSource('…/maps/built')`).

## Licences

**The map data in this folder is not under the package's MIT licence.**

| Data | Source | Licence |
|---|---|---|
| Terrain images, objects, bridges (`terrain.png`, `objects.yaml`) | © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors | [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/) |
| Heights (`heights.png`) | IGN, RGE ALTI® | [Licence Ouverte 2.0 (Etalab)](https://www.etalab.gouv.fr/licence-ouverte-open-licence) |

The built maps are a database derived from OpenStreetMap: they are offered under the
ODbL 1.0, with their heights under the Licence Ouverte 2.0, which is compatible with it.
Each `map.yaml` carries its `attribution`, with the date of its data: anything that
shows a map to players must show it too.

Not used yet: the Copernicus DEM, for maps outside France, has its own licence
(free use, with the attribution "produced using Copernicus WorldDEM-30 © DLR e.V.
2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the
European Union and ESA; all rights reserved").

## Making a map

Downloaded data is untrusted input: fetch it into an empty folder outside the
repository.

```sh
dart run battle_map:fetch_map_sources maps/source/<map>/import.yaml <downloads>
dart run battle_map:import_map <plan> maps/source/<map>/import.yaml <downloads> <source>
# Correct <source> by hand (terrain.png in an image editor, objects.yaml), checking it with:
dart run battle_map:preview_map <source> preview.png
dart run battle_map:build_map <plan> <source> maps/built/<map>
```

`import_map` reports what each rule did and each river crossing it left without a
bridge. To correct a built map again, `dart run battle_map:source_map maps/built/<map>
<source>` writes its source map back. Re-importing gives newer OpenStreetMap data and
drops the corrections below: apply them again.

## saint_lo

Normandy bocage: 10 × 50 km of the Vire valley, from south of Isigny-sur-Mer down
through Saint-Lô (Lambert-93 397–407 km E, 6,867–6,917 km N). OpenStreetMap data of
2026-11-05, heights fetched on 2026-11-05.

Corrections by hand:
- Starting points (in `import.yaml`): HQs at the two ends and spread between them for 3
  to 5 teams; eight relics two by two at the same distance from the middle row, one in
  Saint-Lô; all on open grass or road with free cells around, since relics and the HQ
  are pushed and town streets do not let them through.
- `bridge@(499, 256)` made a `reinforced_bridge`: without it, the north HQ's land (east
  of the Vire, north of row 637) was linked to the rest only by bridges a relic or the
  HQ cannot cross.
