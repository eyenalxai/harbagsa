# Motion

Every motion in the game belongs to the player. The overlay never animates. The
camera has no idle motion.

## The frequency rule

Ask how often the player sees the motion, then decide once.

- The overlay is read, not acted on. It never moves: no fade, no slide, no scale,
  no highlight transition, no easing. The settings menu opens and closes in one
  frame.
- The world moves only when the player moves. No sway, no breathing, no idle
  drift, no ambient camera work.
- Motion the player triggers is smoothed. Motion the player does not trigger does
  not exist.

## Smoothing

Two values use the same exponential filter: the eye height and the step offset.

```text
x += (target - x) * (1 - exp(-rate * dt))
```

Why this shape:

- It is frame-rate independent. A linear `lerp(x, target, 0.2)` moves twice as
  fast at 120 Hz.
- It never overshoots.
- The rate is the inverse time constant. `rate = 18` means a 56 ms time
  constant.

The eye height reaches a new stance in 0.184 s. The step offset settles in
0.256 s. Both are derived from the rate; the eye constant is
`src/game/config.odin:94` and the step constant is `src/game/config.odin:77`.

The step offset starts at the height of the step it absorbed: 0.20 m for one
tread, up to the 0.40 m clamp. From 0.20 m it reaches the 0.001 m floor in about
0.30 s; from 0.40 m it takes about 0.33 s.

| Value | Rate | 1% of the gap | To zero |
| --- | --- | --- | --- |
| Eye height | 25 /s | 0.184 s | asymptotic |
| Step offset | 18 /s | 0.256 s | 0.30 s from 0.20 m, 0.33 s from 0.40 m |

The step test holds the visible result: `tests/simulation/stair.odin` bounds the
per-step eye movement to 0.10 m, half of one 0.20 m tread.

## The camera

| Motion | Formula | Source |
| --- | --- | --- |
| Look | direct delta, no filter | `src/game/player.odin:66` |
| Eye height | exponential to the stance target | `src/game/stance.odin:222` |
| Step offset | accumulated, then exponential to zero | `src/game/step.odin:213` |
| Mantle | smoothstep over 0.25 s, 60% rise then move across | `src/game/mantle.odin:125` |
| Render blend | eye position only, `alpha` from the accumulator | `src/frame/frame.odin:136` |
| TAA jitter | clip space only, not the camera | `src/renderer/shaders/box.vert:31` |

Look applies directly: 0.0022 rad per pixel horizontally, 0.0018 vertically, with
pitch clamped to ±89°. There is no smoothing filter, because the view must answer
the hand.

## What must never exist

- Camera shake, head bob, roll, breathing, or sway.
- A field-of-view punch on sprint, slide, dive, or mantle. The horizontal field of
  view is 90° in every state.
- Recoil or kick.
- A fade or slide on any overlay surface.

If a future feature wants one of these, it is a design change, not a tweak. It
also needs a settings toggle, because some players cannot use it.

There is no reduced-motion setting today. That is not an oversight: there is
nothing to remove. Do not add a setting that does nothing.

## Interpolation

The simulation runs at 60 Hz. The renderer draws at the display rate. The eye
position blends between the last two steps. Rotation does not, because look
applies once per frame.

So vertical camera motion is quantised to 60 Hz and then blended, and rotation is
always current.

## TAA jitter is not camera motion

The jitter is at most ±0.5 px on each axis, added to clip-space XY in the vertex
shader. The camera position, the view matrix, and the projection never change.
The HUD draws after the resolve, so it is never jittered.

## The menu

The menu does not animate. It swaps in one frame, and the selection band moves
without a transition. Key press to redraw is one frame at most.
