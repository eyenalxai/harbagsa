# Third-person spider with two-bone legs

The player is an eight-legged spider seen from a third-person orbit camera. The
body is box geometry. Eight legs each hold a world foot point and solve a
two-bone chain at render rate. The humanoid stance, dive, slide, and mantle rules
are gone.

## Why

- The owner wants the game model replaced, not a camera toggle. The player must
  be a spider with real leg placement, and the camera must show it.
- A first-person view cannot show legs. A third-person view needs a body that
  reads from behind and a camera that stays out of walls.
- The arena is closed and mostly unlit. A body that is only lit by lamps vanishes
  in the dark. The spider's markings are emissive so the player can find it
  without a player light that would break the no-ambient rule.
- The flat box style already has one shader and one mesh. Leg segments are boxes
  between two points, so the spider needs no new mesh, skin, or animation format.

## Decisions

- Replace the humanoid controller. Walk, sprint, and jump stay. Crouch, prone,
  crawl, dive, slide, mantle, stances, movement states, and headroom are removed
  from the model, the input map, and the menu.
- Collision is one capsule: 0.84 m high, 0.42 m in radius. The legs are visual.
  The height fits the 0.90 m tunnel.
- Store a leg's world foot, its previous foot, a swing sample, and a planted
  flag. A planted foot never moves between simulation steps.
- Solve IK analytically: `a = (f^2 - t^2 + d^2) / 2d`, `h = sqrt(f^2 - a^2)`, and
  place the knee `h` along the pole, where the pole points up and outward. Clamp
  the foot to 94 percent of the bone sum, so the chain stays bent.
- Start a swing when a planted foot drifts 0.30 m from its rest point. The rest
  point follows the body yaw. A swing lasts 0.14 s and lifts 0.13 m along an arc
  to a downward ray hit. The landing replant lasts 0.10 s.
- Use an alternating tetrapod. One group of four legs swings at a time, and the
  other four hold the floor. Both groups never swing together.
- Tuck the legs toward the body while airborne, and replant on landing.
- Turn the body toward the horizontal velocity at a 14 /s exponential rate. Look
  moves only the camera, so a strafe turns the spider without turning the view.
- Orbit the camera at 4.4 m, with a pivot 1.03 m above the feet. The initial
  pitch is -15 degrees. A capsule cast from the pivot along the arm shortens the
  distance before the camera crosses geometry, with a 0.12 m pad and a 0.75 m
  minimum. The horizontal field of view stays 90 degrees.
- Append the spider boxes after the arena and placed objects. The count is fixed
  (32 boxes), so TAA keeps index-based history. A planted foot stays still on
  screen; a body-only interpolation would slide it.
- Report the body yaw, the camera yaw and pitch, the planted foot count, and each
  foot in the harness state. Drop the stance and eye fields.

## Considered Options

- **Two-legged spider humanoid.** Rejected. It keeps the humanoid silhouette and
  most of the old controller, and the IK is only two legs. This change is about
  the arachnid gait.
- **Wall climbing.** Deferred. It needs surface-aligned gravity, leg attachment
  to arbitrary normals, and a camera that does not fight the surface. The arena
  is closed, so it also needs an escape or a ceiling rule.
- **A skinned mesh.** Rejected. The renderer has one cube mesh and no skinning.
  Segments as boxes fit the style and need no new pipeline.
- **Animation from a skeleton clip.** Rejected. Foot placement must answer the
  capsule's terrain, which is a query, not a clip.
- **Rigid-body legs on joints.** Rejected. Eight articulated bodies would fight
  the capsule controller, cost physics step time, and still need a foot target.
- **A player light.** Rejected. It would light the floor and break the rule that
  a lamp-free view is black. The emissive eyes and markings keep the spider
  readable and read the baked probe volume like any dynamic box; they add no
  indirect and no player light.
- **Camera smoothing.** Rejected. Look applies directly, as it did in first
  person. The arm is a hard clamp; only the body and feet interpolate.

## Consequences

- The arena code keeps `ARENA_MANTLE_*`, `ARENA_DIVE_*`, and `ARENA_SLIDE_*`;
  the glossary calls those features the West wall, the High platform, and the
  marked strip. The geometry is unchanged.
- The HUD header is now `Spider · Walk` and the state row reports the planted
  foot count.
- The settings menu loses the Crouch and Prone rows.
- The camera can be pulled to 0.75 m in a tight corner. At that distance the body
  fills the view but never clips through the wall.
- The legs do not collide with walls. A leg beside a wall can pass through it.
  A ray per foot finds the floor only.
- The harness reports every foot, so a future change can assert a planted foot
  without reading a PNG.
