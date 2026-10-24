# Recipes: request words to settings

Values are starting points; see `docs/settings.md` for defaults, ranges and
what has been rendered, and `docs/techniques.html` for how each part works.
Presets are in `lib/fc_presets.ps`.

## Piece skeleton

```postscript
%!PS-Adobe-3.0
%%BoundingBox: 0 0 320 200
%%Title: Misty valley
% Status: draft
% Preview: DPI=36 scripts/render.sh gallery/misty_valley.ps

% 1. the piece's own settings (-D can still override each)
/Seed where { pop } { /Seed 7 def } ifelse
/AA where { pop } { /AA true def } ifelse
/Yaw where { pop } { /Yaw -20 def } ifelse
/Pitch where { pop } { /Pitch 2 def } ifelse
/HFov where { pop } { /HFov 55 def } ifelse
/HazeDist where { pop } { /HazeDist 220 def } ifelse

% 2. presets: after the piece's settings (presets never override them),
%    before the landscape
(lib/fc_presets.ps) run
[ /Evening /Clear /Foothills ] fc-presets

% 3. the landscape reads all of the above as it loads
(lib/fc_landscape.ps) run
320 200 fc-landscape
showpage
```

Examples to copy from: `gallery/evening_lake.ps` (presets, lake),
`gallery/alpine_forest.ps` (forest), `gallery/charted_range.ps` (map, river,
lake), `scenes/evening_lake.ps` (scene file), `spikes/ocean_shore.ps` (sea).
A piece's own setting beats a preset's, so write only what differs from
the presets you list.

## Words to settings

| Request says | Try |
|---|---|
| dusk, sunset, golden hour | `/Evening`, or `SunElev` 3 to 8 (sky model) |
| dawn, sunrise | `/Dawn` |
| midday | `/Noon` |
| night, moonlit | `/Night` (moon and stars, `Exposure` 4) |
| misty, foggy, hazy | `HazeDist` 150 to 300, `HazeH` 45 to 80, `Turbidity` 2 to 4 |
| overcast, grey | `/Overcast` |
| stormy, rain | `/Storm` |
| high clouds, wispy | `CloudLayers [/Cumulus /Cirrus]` (layers must not overlap in height) |
| forest, trees | `TreesOn true` (`/Alpine` and `/Foothills` set it); mix with `FsMix` |
| autumn colours | `/Autumn` plus an `FsMix` with larch and broadleaf weights |
| snow, winter | `/Winter`, or a low `SnowLine` |
| lake | `WaterRise` 1.4 (the surface this far above the ground under the camera), or `WaterY` |
| river | `Rivers true` (needs `Erode`) |
| sea, coast, beach | `Ocean true` with `WaterY`; raise `RippleAmp`, set `WindDir` |
| a particular geography | `MapOn true`, `MapFeatures` (peak, ridge, valley, lake), `MapWater` |
| desert, canyon, red rock | `/Mesa` |
| high viewpoint | `CamLift` 0.72 |
| low and moody | `Pitch` 0 to 2, `CamAbove` 5 |
| wide view | `HFov` 64 to 75; a narrower 50 compresses distance |

## Costs (one core)

320x200 takes about 5 minutes and 160x100 (`DPI=36`) about a quarter of that.
1280x800 with `ErN` 1024 is about an hour of core time, so split it with
`render_bands.sh`; the erosion and forest bakes run before the first pixel and
are repeated in every band. Measure with `-D Profile=true`.
