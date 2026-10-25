#+vet explicit-allocators
package game

import "src:geometry"

ARENA_SIZE :: 40.0
ARENA_HALF_SIZE :: ARENA_SIZE * 0.5
ARENA_WALL_HEIGHT :: 4.0
ARENA_WALL_THICKNESS :: 0.5
ARENA_FLOOR_THICKNESS :: 1.0

// Floor and walls first, props next. Placed objects live in Simulation and
// render after this fixed set.
ARENA_BASE_BOX_COUNT :: 5
ARENA_STATIC_BOX_COUNT :: ARENA_BASE_BOX_COUNT + ARENA_PROP_COUNT + ARENA_ROOM_BOX_COUNT

FLOOR_COLOR :: [4]f32{0.42, 0.43, 0.46, 1.0}
WALL_COLOR :: [4]f32{0.55, 0.34, 0.26, 1.0}

arena_static_boxes :: proc() -> []geometry.Box {
	@(static) boxes: [ARENA_STATIC_BOX_COUNT]geometry.Box
	@(static) initialized := false
	if !initialized {
		boxes[0] = {
			center = {0, -ARENA_FLOOR_THICKNESS * 0.5, 0},
			half_extents = {ARENA_HALF_SIZE, ARENA_FLOOR_THICKNESS * 0.5, ARENA_HALF_SIZE},
			color = FLOOR_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		}
		boxes[1] = {
			center = {0, ARENA_WALL_HEIGHT * 0.5, -(ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5)},
			half_extents = {
				ARENA_HALF_SIZE + ARENA_WALL_THICKNESS,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_WALL_THICKNESS * 0.5,
			},
			color = WALL_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		}
		boxes[2] = {
			center = {0, ARENA_WALL_HEIGHT * 0.5, ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5},
			half_extents = {
				ARENA_HALF_SIZE + ARENA_WALL_THICKNESS,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_WALL_THICKNESS * 0.5,
			},
			color = WALL_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		}
		boxes[3] = {
			center = {-(ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5), ARENA_WALL_HEIGHT * 0.5, 0},
			half_extents = {
				ARENA_WALL_THICKNESS * 0.5,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_HALF_SIZE,
			},
			color = WALL_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		}
		boxes[4] = {
			center = {ARENA_HALF_SIZE + ARENA_WALL_THICKNESS * 0.5, ARENA_WALL_HEIGHT * 0.5, 0},
			half_extents = {
				ARENA_WALL_THICKNESS * 0.5,
				ARENA_WALL_HEIGHT * 0.5,
				ARENA_HALF_SIZE,
			},
			color = WALL_COLOR,
			rotation = geometry.IDENTITY_ROTATION,
		}

		props_end := ARENA_BASE_BOX_COUNT + ARENA_PROP_COUNT
		build_arena_props(boxes[ARENA_BASE_BOX_COUNT:props_end])
		build_arena_room(boxes[props_end:ARENA_STATIC_BOX_COUNT])
		initialized = true
	}
	return boxes[:]
}
