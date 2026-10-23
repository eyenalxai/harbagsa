#+vet explicit-allocators
package game

import "core:math"
import b3 "libs:box3d"

import "src:geometry"

@(private)
static_box :: proc(
	center, half_extents: [3]f32,
	color: [4]f32,
	rotation := geometry.IDENTITY_ROTATION,
) -> geometry.Box {
	return {
		center = center,
		half_extents = half_extents,
		color = color,
		rotation = rotation,
	}
}

@(private)
ramp_box :: proc(spec: Ramp_Spec) -> geometry.Box {
	thickness: f32 = 0.30
	half_length: f32 = spec.length * 0.5
	half_width: f32 = ARENA_RAMP_WIDTH * 0.5
	half_thickness: f32 = thickness * 0.5
	center_y: f32 = half_length * math.sin(spec.angle) - half_thickness * math.cos(spec.angle)
	center_z: f32 = ARENA_RAMP_LOW_Z - half_length * math.cos(spec.angle)
	q := b3.MakeQuatFromAxisAngle({1.0, 0.0, 0.0}, spec.angle)
	return static_box(
		{spec.x, center_y, center_z},
		{half_width, half_thickness, half_length},
		WALKABLE_COLOR,
		{q.x, q.y, q.z, q.w},
	)
}

@(private)
ramp_platform :: proc(spec: Ramp_Spec) -> geometry.Box {
	top: f32 = spec.length * math.sin(spec.angle)
	high_z: f32 = ARENA_RAMP_LOW_Z - spec.length * math.cos(spec.angle)
	return static_box(
		{spec.x, top * 0.5, high_z - ARENA_RAMP_PLATFORM_DEPTH * 0.5},
		{ARENA_RAMP_WIDTH * 0.5, top * 0.5, ARENA_RAMP_PLATFORM_DEPTH * 0.5},
		WALKABLE_COLOR,
	)
}

// Fills the static prop slice. The caller owns the slice and the ordering.
@(private)
build_arena_props :: proc(boxes: []geometry.Box) {
	index := 0

	for i in 0 ..< ARENA_STAIR_COUNT {
		top := ARENA_STAIR_RISE * f32(i + 1)
		z := ARENA_STAIR_START_Z - (f32(i) + 0.5) * ARENA_STAIR_RUN
		boxes[index] = static_box(
			{ARENA_STAIR_X, top * 0.5, z},
			{ARENA_RAMP_WIDTH * 0.5, top * 0.5, ARENA_STAIR_RUN * 0.5},
			WALKABLE_COLOR,
		)
		index += 1
	}
	boxes[index] = static_box(
		{
			ARENA_STAIR_X,
			ARENA_STAIR_TOP * 0.5,
			-ARENA_STAIR_PLATFORM_DEPTH * 0.5,
		},
		{ARENA_RAMP_WIDTH * 0.5, ARENA_STAIR_TOP * 0.5, ARENA_STAIR_PLATFORM_DEPTH * 0.5},
		WALKABLE_COLOR,
	)
	index += 1

	boxes[index] = static_box(
		{ARENA_STEP_035_X, 0.35 * 0.5, ARENA_STEP_035_Z},
		{ARENA_STEP_HALF, 0.35 * 0.5, ARENA_STEP_HALF},
		WALKABLE_COLOR,
	)
	index += 1
	boxes[index] = static_box(
		{ARENA_STEP_050_X, 0.50 * 0.5, ARENA_STEP_050_Z},
		{ARENA_STEP_HALF, 0.50 * 0.5, ARENA_STEP_HALF},
		WALKABLE_COLOR,
	)
	index += 1

	ramps := [3]Ramp_Spec {
		{ARENA_RAMP_20_X, ARENA_RAMP_20_LENGTH, 20.0 * math.PI / 180.0},
		{ARENA_RAMP_40_X, ARENA_RAMP_40_LENGTH, 40.0 * math.PI / 180.0},
		{ARENA_RAMP_50_X, ARENA_RAMP_50_LENGTH, 50.0 * math.PI / 180.0},
	}
	for spec in ramps {
		boxes[index] = ramp_box(spec)
		index += 1
		boxes[index] = ramp_platform(spec)
		index += 1
	}

	tunnels := [3]Tunnel_Spec {
		{ARENA_TUNNEL_135_X, ARENA_TUNNEL_135_CLEARANCE},
		{ARENA_TUNNEL_122_X, ARENA_TUNNEL_122_CLEARANCE},
		{ARENA_TUNNEL_090_X, ARENA_TUNNEL_090_CLEARANCE},
	}
	for spec in tunnels {
		ceiling_half_y := (ARENA_WALL_HEIGHT - spec.clearance) * 0.5
		ceiling_center_y := spec.clearance + ceiling_half_y
		boxes[index] = static_box(
			{spec.x, ceiling_center_y, ARENA_TUNNEL_Z},
			{ARENA_TUNNEL_WIDTH * 0.5, ceiling_half_y, ARENA_TUNNEL_DEPTH * 0.5},
			TUNNEL_COLOR,
		)
		index += 1
		sides := [2]f32{-1.0, 1.0}
		for side in sides {
			boxes[index] = static_box(
				{spec.x + side * 1.75, ARENA_WALL_HEIGHT * 0.5, ARENA_TUNNEL_Z},
				{
					ARENA_TUNNEL_WALL_THICKNESS * 0.5,
					ARENA_WALL_HEIGHT * 0.5,
					ARENA_TUNNEL_DEPTH * 0.5,
				},
				TUNNEL_COLOR,
			)
			index += 1
		}
	}

	for i in 0 ..< ARENA_SLIDE_MARKER_COUNT {
		z := ARENA_SLIDE_START_Z - f32(i) * ARENA_SLIDE_MARKER_SPACING
		boxes[index] = static_box(
			{ARENA_SLIDE_MARKER_X, 0.5, z},
			{0.05, 0.5, 0.05},
			LANE_COLOR,
		)
		boxes[index].visual_only = true
		index += 1
	}

	boxes[index] = static_box(
		{ARENA_MANTLE_12_X, ARENA_MANTLE_12_HEIGHT * 0.5, ARENA_MANTLE_Z},
		{
			ARENA_MANTLE_WIDTH * 0.5,
			ARENA_MANTLE_12_HEIGHT * 0.5,
			ARENA_MANTLE_DEPTH * 0.5,
		},
		MANTLE_COLOR,
	)
	index += 1
	boxes[index] = static_box(
		{ARENA_MANTLE_15_X, ARENA_MANTLE_15_HEIGHT * 0.5, ARENA_MANTLE_Z},
		{
			ARENA_MANTLE_WIDTH * 0.5,
			ARENA_MANTLE_15_HEIGHT * 0.5,
			ARENA_MANTLE_DEPTH * 0.5,
		},
		MANTLE_COLOR,
	)
	index += 1

	boxes[index] = static_box(
		{
			ARENA_DIVE_PLATFORM_X,
			ARENA_DIVE_PLATFORM_HEIGHT * 0.5,
			ARENA_DIVE_PLATFORM_Z,
		},
		{
			ARENA_DIVE_PLATFORM_WIDTH * 0.5,
			ARENA_DIVE_PLATFORM_HEIGHT * 0.5,
			ARENA_DIVE_PLATFORM_DEPTH * 0.5,
		},
		DIVE_COLOR,
	)
	index += 1

	for i in 0 ..< ARENA_DIVE_STAIR_COUNT {
		top := ARENA_DIVE_STAIR_RISE * f32(i + 1)
		z := ARENA_DIVE_STAIR_START_Z - (f32(i) + 0.5) * ARENA_DIVE_STAIR_RUN
		boxes[index] = static_box(
			{ARENA_DIVE_PLATFORM_X, top * 0.5, z},
			{ARENA_DIVE_PLATFORM_WIDTH * 0.5 - 1.0, top * 0.5, ARENA_DIVE_STAIR_RUN * 0.5},
			DIVE_COLOR,
		)
		index += 1
	}

	boxes[index] = static_box(
		{
			ARENA_DIVE_PLATFORM_X,
			0.005,
			ARENA_DIVE_LANDING_Z,
		},
		{
			ARENA_DIVE_LANDING_WIDTH * 0.5,
			0.005,
			ARENA_DIVE_LANDING_DEPTH * 0.5,
		},
		DIVE_COLOR,
	)
	boxes[index].visual_only = true
	index += 1

	assert(index == len(boxes))
}
