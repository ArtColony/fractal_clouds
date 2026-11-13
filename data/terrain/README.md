# Terrain grids

Real elevation grids made by `scripts/dem_fetch.py` (#155). Each `NAME.bin` is a grid of little-endian binary64 heights in metres. Its `NAME.json` records the source, tiles, licence, attribution, centre, size, cell and projection. See `docs/spikes/155-dem-fetch/README.md`.

`grand_canyon`: produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018, provided under COPERNICUS by the European Union and ESA; all rights reserved.

`grand_canyon_layers.ps` is the canyon's rock beds for `lib/fc_layers.ps` (#160): base elevations from the Bright Angel Trail section, with colours picked by eye against a public-domain NPS photo. See `docs/spikes/160-strata/README.md`.
