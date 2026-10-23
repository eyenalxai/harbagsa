#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package renderer_test

import "core:math/linalg"
import "core:testing"

import "src:game"
import "src:renderer"

TEST_LIGHT_DIRECTION :: [3]f32{-0.45, -1.0, -0.35}

// The arena volume: floor bottom to wall top, plus the wall thickness.
arena_corners :: proc() -> [8][3]f32 {
	half: f32 = game.ARENA_HALF_SIZE + game.ARENA_WALL_THICKNESS
	low: f32 = -game.ARENA_FLOOR_THICKNESS
	high: f32 = game.ARENA_WALL_HEIGHT
	return {
		{-half, low, -half},
		{half, low, -half},
		{half, high, -half},
		{-half, high, -half},
		{-half, low, half},
		{half, low, half},
		{half, high, half},
		{-half, high, half},
	}
}

transform :: proc(m: renderer.Mat4, point: [3]f32) -> [4]f32 {
	return {
		m[0] * point.x + m[4] * point.y + m[8] * point.z + m[12],
		m[1] * point.x + m[5] * point.y + m[9] * point.z + m[13],
		m[2] * point.x + m[6] * point.y + m[10] * point.z + m[14],
		m[3] * point.x + m[7] * point.y + m[11] * point.z + m[15],
	}
}

expect_near :: proc(t: ^testing.T, actual, expected: f32, message: string) {
	testing.expectf(t, abs(actual - expected) <= 0.0001, "%s: got %v, want %v", message, actual, expected)
}

@(test)
orthographic_maps_near_and_far_to_the_depth_range :: proc(t: ^testing.T) {
	m := renderer.mat4_orthographic(-1, 1, -1, 1, 1, 3)
	expect_near(t, transform(m, {0, 0, -1}).z, 0, "near plane")
	expect_near(t, transform(m, {0, 0, -3}).z, 1, "far plane")
}

@(test)
orthographic_flips_the_y_axis :: proc(t: ^testing.T) {
	m := renderer.mat4_orthographic(-1, 1, -1, 1, 1, 3)
	expect_near(t, transform(m, {0, 1, -1}).y, -1, "top edge")
	expect_near(t, transform(m, {0, -1, -1}).y, 1, "bottom edge")
}

@(test)
light_volume_contains_the_arena :: proc(t: ^testing.T) {
	m := renderer.shadow_light_matrix(TEST_LIGHT_DIRECTION)
	for corner in arena_corners() {
		clip := transform(m, corner)
		testing.expectf(t, clip.w > 0, "corner %v is behind the light: w=%v", corner, clip.w)
		ndc := [3]f32{clip.x / clip.w, clip.y / clip.w, clip.z / clip.w}
		testing.expectf(
			t,
			ndc.x >= -1 && ndc.x <= 1 && ndc.y >= -1 && ndc.y <= 1 && ndc.z >= 0 && ndc.z <= 1,
			"corner %v is outside the shadow volume: %v",
			corner,
			ndc,
		)
	}
}

@(test)
shadow_depth_grows_away_from_the_sun :: proc(t: ^testing.T) {
	m := renderer.shadow_light_matrix(TEST_LIGHT_DIRECTION)
	to_light := linalg.vector_normalize(
		[3]f32{-TEST_LIGHT_DIRECTION.x, -TEST_LIGHT_DIRECTION.y, -TEST_LIGHT_DIRECTION.z},
	)
	center := renderer.LIGHT_VOLUME_CENTER

	near := transform(m, center + to_light * 5)
	far := transform(m, center - to_light * 5)
	testing.expectf(t, near.z < far.z, "depth did not grow away from the sun: near %v, far %v", near.z, far.z)
}
