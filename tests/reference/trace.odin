#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package reference_test

import "core:math"
import "core:testing"

import "src:geometry"
import "src:reference"

RECEIVER_COLOR :: [4]f32{0.8, 0.8, 0.8, 1.0}
EMITTER_COLOR :: [4]f32{0.5, 0.5, 0.5, 1.0}
EMITTER_STRENGTH :: f32(2.0)
RECEIVER_ALBEDO :: RECEIVER_COLOR.r
EMITTER_EMISSION :: EMITTER_COLOR.r * EMITTER_STRENGTH

box :: proc(center, half_extents: [3]f32, color: [4]f32, emissive: f32 = 0) -> geometry.Box {
	return {
		center = center,
		half_extents = half_extents,
		color = color,
		rotation = geometry.IDENTITY_ROTATION,
		emissive = emissive,
	}
}

// The furnace test: a large emissive plane covers almost all of the upper
// hemisphere, so a cosine-weighted path sees a constant radiance. With two
// bounces the second vertex bounces back to the receiver and stops, so the
// receiver's indirect term must be `albedo * emission`. A missing or doubled
// pi shows immediately.
@(test)
test_furnace_plane :: proc(t: ^testing.T) {
	boxes := []geometry.Box {
		// The receiver: top face at y = 0.
		box({0, -1, 0}, {50, 1, 50}, RECEIVER_COLOR),
		// The emitter: bottom face at y = 1.9.
		box({0, 2, 0}, {50, 0.1, 50}, EMITTER_COLOR, EMITTER_STRENGTH),
	}
	scene := reference.Scene {
		boxes = boxes,
		camera = {position = {0, 0.05, 0}, pitch = -math.PI * 0.5, fov_x = math.PI * 0.5},
	}
	settings := reference.Settings{samples = 512, bounces = 2, stride = 1}
	grid := reference.estimate(scene, settings, 1, 1, context.allocator)
	defer reference.Grid_Destroy(&grid, context.allocator)
	testing.expect_value(t, len(grid.samples), 1)
	sample := grid.samples[0]
	testing.expect(t, !sample.sky && !sample.edge)
	expected := RECEIVER_ALBEDO * EMITTER_EMISSION
	testing.expectf(
		t,
		abs(sample.indirect.x - expected) < 0.01,
		"furnace indirect %.4f, expected %.4f",
		sample.indirect.x,
		expected,
	)
}

@(test)
test_point_light :: proc(t: ^testing.T) {
	floor := box({0, -1, 0}, {10, 1, 10}, RECEIVER_COLOR)
	lamp := box({0, 2, 0}, {0.2, 0.2, 0.2}, {1, 0.78, 0.45, 1}, 0.8)
	scene := reference.Scene {
		boxes = []geometry.Box{floor, lamp},
		lights = []reference.Light {
			{position = {0, 2, 0}, color = {1, 0.5, 0.25}, intensity = 1, range = 10},
		},
		camera = {position = {0.5, 2, 0}, pitch = -math.PI * 0.5, fov_x = math.PI * 0.5},
	}
	settings := reference.Settings{samples = 4, bounces = 2, stride = 1}
	grid := reference.estimate(scene, settings, 1, 1, context.allocator)
	defer reference.Grid_Destroy(&grid, context.allocator)
	sample := grid.samples[0]
	// The hit is (0.5, 0, 0); the light is 2.0616 m away at (0, 2, 0).
	distance := f32(math.sqrt(0.5 * 0.5 + 2.0 * 2.0))
	cosine := 2.0 / distance
	reach := distance / 10.0
	falloff := (1.0 - reach * reach) * (1.0 - reach * reach)
	expected := [3]f32{1, 0.5, 0.25} * (RECEIVER_ALBEDO * cosine * falloff)
	testing.expectf(t, abs(sample.direct.x - expected.x) < 1e-3, "lamp direct %v", sample.direct)
	testing.expectf(t, abs(sample.direct.z - expected.z) < 1e-3, "lamp direct %v", sample.direct)

	blocker := box({0.25, 1, 0}, {0.2, 0.2, 0.2}, RECEIVER_COLOR)
	scene.boxes = []geometry.Box{floor, blocker}
	blocked := reference.estimate(scene, settings, 1, 1, context.allocator)
	defer reference.Grid_Destroy(&blocked, context.allocator)
	direct := blocked.samples[0].direct
	testing.expectf(t, abs(direct.x) < 1e-6 && abs(direct.z) < 1e-6, "blocked direct %v", direct)
}

@(test)
test_camera_ray_basis :: proc(t: ^testing.T) {
	camera := reference.Camera{position = {1, 2, 3}, fov_x = math.PI * 0.5}
	top_left := reference.camera_ray(camera, 2, 2, 0, 0)
	testing.expect(t, top_left.x < 0 && top_left.y > 0 && top_left.z < 0)
	bottom_right := reference.camera_ray(camera, 2, 2, 1, 1)
	testing.expect(t, bottom_right.x > 0 && bottom_right.y < 0 && bottom_right.z < 0)
}

@(test)
test_compare_ratio :: proc(t: ^testing.T) {
	grid := reference.Grid {
		width = 2,
		height = 1,
		stride = 1,
		frame_width = 2,
		frame_height = 1,
		samples = []reference.Sample {
			{x = 0, y = 0, indirect = {0.1, 0.1, 0.1}},
			{x = 1, y = 0, indirect = {0.2, 0.2, 0.2}},
		},
	}
	direct := []f32{0, 0, 0, 0, 0, 0, 0, 0}
	lit := []f32{0.2, 0.2, 0.2, 0, 0.2, 0.2, 0.2, 0}
	comparison := reference.compare(lit, direct, 2, 1, grid, context.allocator)
	defer reference.Comparison_Destroy(&comparison, context.allocator)
	testing.expect_value(t, comparison.metrics.points, 2)
	testing.expectf(
		t,
		abs(comparison.metrics.ratio - 1.5) < 1e-5,
		"median ratio %v",
		comparison.metrics.ratio,
	)
	testing.expectf(
		t,
		abs(comparison.metrics.energy.x - 4.0 / 3.0) < 1e-5,
		"energy %v",
		comparison.metrics.energy,
	)
	testing.expect_value(t, comparison.metrics.colour_spread, 0)
}

@(test)
test_sky_miss :: proc(t: ^testing.T) {
	scene := reference.Scene {
		camera = {position = {0, 0, 0}, fov_x = math.PI * 0.5},
	}
	settings := reference.Settings{samples = 1, bounces = 2, stride = 1}
	grid := reference.estimate(scene, settings, 1, 1, context.allocator)
	defer reference.Grid_Destroy(&grid, context.allocator)
	sample := grid.samples[0]
	testing.expect(t, sample.sky)
	direction := reference.camera_ray(scene.camera, 1, 1, 0, 0)
	expected := reference.sky_gradient(direction)
	testing.expect_value(t, sample.radiance, expected)
}
