# Third-person spider

The player is an eight-legged spider. The captures come from the scenario, not
from a hand-taken screenshot:

```sh
./bin/harbagsa-agent run scenarios/spider-view.json --out runs/evidence-spider
```

`spawn.png`, `walk.png`, and `lit.png` show the spider from behind at 1280x720.
The first two are the dark spawn area; `lit.png` is beside the warm lamp. The
scenario also asserts that the emissive markings are visible in the spawn view
(`stats.max.x > 200`, `stats.max.z < 150`) and that the lit view is not black
(`stats.mean.y > 5`).

## What the frames show

- The body is two boxes: a cephalothorax and an abdomen. Eight legs each have a
  femur and a tibia, with a knee box at the joint.
- The knees rise above the abdomen line. The feet spread to a 2.0 m leg span.
- Two amber marking boxes sit on the abdomen top. They are the only part of the
  spider that is visible in a lamp-free view.
- The floor under the spider is unlit at spawn and lit near the warm lamp. There
  is no player light.

## Numbers

- 32 spider boxes: 2 body, 4 eyes, 2 markings, 8 femurs, 8 tibias, 8 knees.
- Legs: femur 0.62 m, tibia 0.70 m, reach 94 percent of the sum.
- Stance: 0.30 m drift starts a swing; a swing lasts 0.14 s and lifts 0.13 m.
- Camera: 4.4 m arm, 1.03 m pivot, -15 degree default pitch, 0.75 m minimum.

## Checks

`scenarios/spider-ik.json` asserts eight planted feet at rest, at least four
planted in a walk and a sprint, every foot within 0.2 m of the floor during the
sprint, zero planted in the first airborne step, and a replant on landing. `scenarios/spider-camera.json` asserts the behind view, the wall
pull-in, and the +45 degree pitch clamp.
