# Spike: do pinned peaks land where the map puts them? (#13)

**Question:** #13 asks for a peak placed on a map (`lib/fc_map.ps`) to land
within about one ridge wavelength (~90 units) of where it was put, even
though the ridges themselves are noise.

**Answer: yes.** Summits land 10–32 units from the placed point over four
seeds. Heights come within about 15% of the requested height.

## Method

`spikes/map_pins.ps` runs a map piece's plan (default
`gallery/charted_range.ps`, erosion off). For every `/peak` it then searches
the disc of radius `spread` around the peak in 5-unit steps for the highest
procedural ground (`fc-height-proc`, 6 octaves). It prints that summit's
height and its distance from the placed point:

    scripts/render.sh -D Seed=3 spikes/map_pins.ps

Near a feature the map sets the pin to 1, and the domain warp fades by it
(`MapPin`), so the ridges there keep to the noise's own unwarped network.
The peak's bump raises the massif mask, and the highest crest under the bump
becomes the summit.

## Results

Charted range, West Twin asked 48 at (−170, 180) with spread 130; East Twin
asked 44 at (190, 185) with spread 120. pscat 0.6.2 on macOS.

| Seed | West Twin: height, distance | East Twin: height, distance |
|---|---|---|
| 3  | 43.2, 32 | 37.2, 32 |
| 5  | 52.2, 10 | 42.2, 18 |
| 11 | 49.6, 18 | 39.0, 10 |
| 23 | 48.1, 11 | 44.3, 18 |

## Notes

- **Height calibration.** `fc-map-mask-for` assumes ridges ≈ 0.85 on the
  top crest under a bump. That figure came from these runs: assuming 1 put
  every summit about 15% low.
- **Search radius.** A first version searched twice the spread. At seed 11
  it found the main ridge 178 units away instead of the East Twin, because
  the ground outside the bump isn't the peak's.
- **What didn't come out of this.** Pinning the crest itself (blending the
  ridges toward 1 at the centre) would land summits exactly but give them
  domed tops, so I didn't do it.
- **Painted grids.** A painted grid doesn't pin, so grid mountains keep the
  usual warp.
