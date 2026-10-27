# Motion

Every motion in the game belongs to the player. The overlay never animates. The
camera has no idle motion.

## The frequency rule

Ask how often the player sees the motion, then decide once.

- The overlay is read, not acted on. It never moves: no fade, no slide, no scale,
  no highlight transition, no easing. The settings menu opens and closes in one
  frame.
- The world moves only when the player moves. No sway, no breathing, no idle
  camera work, no idle leg tap. The spider's legs are still when the player is
  still.
- Motion the player triggers is smoothed where a value has a target. The legs
  use timed arcs, not a filter.

## Smoothing

One value uses the exponential filter: the step offset. The body yaw uses it
too, toward the movement direction.

```text
x += (target - x) * (1 - exp(-rate * dt))
```

Why this shape:

- It is frame-rate independent. A linear `lerp(x, target, 0.2)` moves twice as
  fast at 120 Hz.
- It never overshoots.
- The rate is the inverse time constant. `rate = 18` means a 56 ms time
  constant.

The step offset starts at the height of the step it absorbed: 0.20 m for one
tread, up to the 0.40 m clamp. From 0.20 m it reaches the 0.001 m floor in about
0.30 s; from 0.40 m it takes about 0.33 s. The camera pivot carries it; the body
does not move.

The body yaw turns at 14 /s. A 90 degree turn closes 99 percent in 0.33 s. A
speed below 0.20 m/s keeps the last heading, so the spider does not spin in
place when the stick is released.

## The legs

| Motion | Formula | Source |
| --- | --- | --- |
| Stance | planted feet hold their world point | `src/game/spider.odin` |
| Swing | smoothstep over 0.14 s plus a 0.13 m arc | `src/game/spider.odin` |
| Landing | 0.10 s replant after the feet tuck | `src/game/spider.odin` |
| Body yaw | exponential to the movement direction, 14 /s | `src/game/player.odin` |
| Knee | analytic two-bone solve, pole up and out | `src/game/spider.odin` |

A plantar foot steps when it drifts 0.30 m from its rest point. One tetrapod
group swings at a time: front-left, rear-left, front-right, and rear-right, then
the other four. Both groups never swing together. A foot target past 94 percent
of the bone sum is pulled toward the hip, so a leg never locks straight.

## The camera

| Motion | Formula | Source |
| --- | --- | --- |
| Look | direct delta, no filter | `src/game/player.odin` |
| Orbit yaw | direct, movement input is relative to it | `src/game/player.odin` |
| Orbit pitch | direct, clamped from -70 to +45 degrees | `src/game/player.odin` |
| Spring arm | capsule cast from the pivot, hard clamp | `src/game/camera.odin` |
| Render blend | body position, body yaw, and the eight feet | `src/frame/frame.odin` |
| TAA jitter | clip space only, not the camera | `src/renderer/shaders/box.vert` |

Look applies directly: 0.0022 rad per pixel horizontally, 0.0018 vertically. The
pitch clamp is a third-person range, not the old first-person +-89 degrees. There
is no smoothing filter, because the view must answer the hand.

The spring arm is a capsule cast from the pivot to the desired camera point. A
hit shortens the arm to the hit fraction minus a 0.12 m pad, never below 0.75 m.
A ray from the feet finds a low ceiling. When the ceiling is below the pivot, the
pivot drops under it and a downward look flattens to level, so the tunnel view
stays inside the shell.
The arm does not ease out of a wall: the camera must never clip, and a wall that
appears for one frame must push the camera for one frame.

## Interpolation

The simulation runs at 60 Hz. The renderer draws at the display rate. The body
position, the body yaw, and the eight foot targets blend between the last two
steps. The knees are solved at render rate from those blended points, so a
planted foot is still and a swinging foot is smooth at the display rate. Camera
rotation is always current.

## What must never exist

- Idle leg motion, an idle sway, or a breathing body.
- Camera shake, head bob, roll, or sway.
- A field-of-view punch on sprint or jump. The horizontal field of view is 90
  degrees in every state.
- Recoil or kick.
- A fade or slide on any overlay surface.
- A camera that eases out of a wall.

If a future feature wants one of these, it is a design change, not a tweak. It
also needs a settings toggle, because some players cannot use it. There is no
reduced-motion setting today. That is not an oversight: there is nothing to
remove.

## The menu

The menu does not animate. It swaps in one frame, and the selection band moves
without a transition. Key press to redraw is one frame at most.
