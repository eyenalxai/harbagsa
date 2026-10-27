#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package renderer_test

import "core:log"
import "core:math"
import "core:testing"

import "src:geometry"
import "src:renderer"

TEST_CAMERA :: renderer.Camera {
	position = {0, 1.4, 3.5},
	yaw      = 0,
	pitch    = -0.3,
	fov_x    = math.PI * 0.5,
}

@(test)
point_light_lights_a_box_and_reaches_the_buffer :: proc(t: ^testing.T) {
	device: Test_Device
	if !open_test_device(&device) {
		log.info("skipping the point light test: no Vulkan device")
		return
	}
	defer close_test_device(&device)
	state := &device.state
	disable_taa(state)

	box := geometry.Box {
		center       = {0, 0, 0},
		half_extents = {2, 2, 0.25},
		color        = {0.5, 0.5, 0.5, 1},
	}
	view := renderer.Render_Input {
		camera = renderer.Camera{position = {0, 0, 5}, fov_x = math.PI * 0.5},
		boxes = []geometry.Box{box},
	}

	dark := sample_point(state, view, {0, 0, 0.25})
	dark_digest := state.render_digest
	testing.expectf(t, dark >= 0, "the unlit frame did not render")
	testing.expectf(t, dark < 0.001, "an unlit box is not black: %f", dark)

	lights := []renderer.Light {
		{position = {0, 0, 3}, intensity = 4, color = {1, 1, 1}, range = 10},
	}
	view.lights = lights
	lit := sample_point(state, view, {0, 0, 0.25})
	testing.expectf(t, lit >= 0, "the lit frame did not render")
	testing.expectf(t, lit > dark + 0.2, "the point light did not brighten the box: %f -> %f", dark, lit)
	testing.expect(
		t,
		state.render_digest.value != dark_digest.value,
		"the light did not change the render digest",
	)

	report := renderer.renderer_report(state)
	testing.expect_value(t, report.light_count, 1)
	uploaded := renderer.lights_uploaded(state)
	testing.expect_value(t, len(uploaded), 1)
	if len(uploaded) == 1 {
		testing.expect_value(t, uploaded[0].position, [3]f32{0, 0, 3})
		testing.expect_value(t, uploaded[0].intensity, f32(4))
		testing.expect_value(t, uploaded[0].color, [3]f32{1, 1, 1})
		testing.expect_value(t, uploaded[0].range, f32(10))
	}

	many := [96]renderer.Light{}
	for &light in many {
		light = lights[0]
	}
	view.lights = many[:]
	_, _, _, many_ok := draw_scene(state, view)
	testing.expect(t, many_ok, "the 96-light frame did not render")
	testing.expect_value(t, renderer.renderer_report(state).light_count, 96)
	testing.expect_value(t, len(renderer.lights_uploaded(state)), 96)

	view.lights = nil
	dark_again := sample_point(state, view, {0, 0, 0.25})
	testing.expectf(t, dark_again >= 0, "the second unlit frame did not render")
	testing.expectf(t, dark_again < 0.001, "removing the light left a fill: %f", dark_again)
	testing.expectf(t, dark_again < lit, "removing the light left the contribution: %f", dark_again)
}

@(test)
point_light_shadow_hides_a_blocked_surface :: proc(t: ^testing.T) {
	device: Test_Device
	if !open_test_device(&device) {
		log.info("skipping the point light shadow test: no Vulkan device")
		return
	}
	defer close_test_device(&device)
	state := &device.state
	disable_taa(state)

	wall := geometry.Box {
		center       = {0, 0, -0.25},
		half_extents = {4, 4, 0.25},
		color        = {0.8, 0.8, 0.8, 1},
	}
	occluder := geometry.Box {
		center       = {1, 0.5, 1},
		half_extents = {0.5, 0.5, 0.5},
		color        = {0.2, 0.2, 0.2, 1},
	}
	target := [3]f32{0, 0, 0}
	offset := [3]f32{target.x - (-2), target.y - 1.5, target.z - 4}
	horizontal := math.sqrt(offset.x * offset.x + offset.z * offset.z)
	view := renderer.Render_Input {
		camera = renderer.Camera {
			position = {-2, 1.5, 4},
			yaw      = math.atan2(-offset.x, -offset.z),
			pitch    = math.atan2(offset.y, horizontal),
			fov_x    = math.PI * 0.5,
		},
		boxes = []geometry.Box{wall, occluder},
		lights = []renderer.Light {
			{position = {2, 1, 2}, intensity = 4, color = {1, 1, 1}, range = 10},
		},
	}
	debug := renderer.renderer_debug(state)
	debug.light_shadows = false
	renderer.set_renderer_debug(state, debug)
	open_value := sample_point(state, view, {0, 0, 0.01})
	open_digest := state.render_digest

	debug.light_shadows = true
	renderer.set_renderer_debug(state, debug)
	shadow_value := sample_point(state, view, {0, 0, 0.01})

	testing.expectf(
		t,
		open_value > shadow_value + 0.2,
		"the blocked surface did not darken: %f -> %f",
		open_value,
		shadow_value,
	)
	testing.expect(
		t,
		state.render_digest.value != open_digest.value,
		"the shadow toggle did not change the render digest",
	)
}

@(test)
emissive_box_draws_without_a_light :: proc(t: ^testing.T) {
	device: Test_Device
	if !open_test_device(&device) {
		log.info("skipping the emissive box test: no Vulkan device")
		return
	}
	defer close_test_device(&device)
	state := &device.state
	disable_taa(state)

	box := geometry.Box {
		center       = {0, 1, 0},
		half_extents = {0.3, 0.3, 0.3},
		color        = {0.5, 0.5, 0.5, 1},
	}
	view := renderer.Render_Input {
		camera = TEST_CAMERA,
		boxes  = []geometry.Box{box},
	}
	dark := sample_point(state, view, {0, 1, 0.3})
	box.emissive = 1
	view.boxes = []geometry.Box{box}
	lit := sample_point(state, view, {0, 1, 0.3})
	testing.expectf(
		t,
		lit > dark + 0.2,
		"the emissive term did not draw without a light: %f -> %f",
		dark,
		lit,
	)
}
