# Lamp shadow evidence

The direct lighting path is point lights. Each active lamp casts one hard ray per
fragment. The edge is sharp at contact and has no penumbra; the scene uses the
probe field for the diffuse bounce and ambient occlusion for contact darkening.

## Scenarios

- `scenarios/lamp-wall-plane.json` places a lamp on a wall and captures the wall
  before and after a crate is placed. It gates the shadow fan and the point-light
  shadow switch.
- `scenarios/stairs-ao.json` places a lamp above the dive stairs and captures the
  stairs with ambient occlusion on and off.
- `scenarios/ramp-shadow.json` and `scenarios/ramp-shadow-crouch.json` use a lamp
  under the 20 degree ramp and gate the step amplitude in the shaded region.

Run one into a run directory and read the PNGs from `frames/`:

```sh
./bin/harbagsa-agent run scenarios/lamp-wall-plane.json --out runs/lamp-wall
./bin/harbagsa-agent run scenarios/stairs-ao.json --out runs/stairs-ao
```

The offscreen captures use the same renderer path as the game window.
