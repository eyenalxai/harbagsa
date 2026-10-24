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
	view := renderer.Frame_View {
		camera          = renderer.Camera{position = {0, 0, 5}, fov_x = math.PI * 0.5},
		light_direction = {0, -1, 0},
		boxes           = []geometry.Box{box},
	}

	dark_values, _, _, dark_ok := draw_scene(state, view)
	dark := mean_luminance(dark_values)
	dark_digest := state.render_digest
	testing.expect(t, dark_ok, "the unlit frame did not render")

	lights := []renderer.Light {
		{position = {0, 0, 3}, intensity = 4, color = {1, 1, 1}, range = 10},
	}
	view.lights = lights
	lit_values, _, _, lit_ok := draw_scene(state, view)
	lit := mean_luminance(lit_values)
	testing.expect(t, lit_ok, "the lit frame did not render")
	testing.expectf(t, lit > dark * 1.2, "the point light did not brighten the box: %f -> %f", dark, lit)
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

	many := [10]renderer.Light{}
	for &light in many {
		light = lights[0]
	}
	view.lights = many[:]
	_, _, _, many_ok := draw_scene(state, view)
	testing.expect(t, many_ok, "the ten-light frame did not render")
	testing.expect_value(t, renderer.renderer_report(state).light_count, renderer.MAX_POINT_LIGHTS)
	testing.expect_value(t, len(renderer.lights_uploaded(state)), renderer.MAX_POINT_LIGHTS)

	view.lights = nil
	dark_again_values, _, _, again_ok := draw_scene(state, view)
	testing.expect(t, again_ok, "the second unlit frame did not render")
	dark_again := mean_luminance(dark_again_values)
	testing.expectf(t, dark_again < lit, "removing the light left the contribution: %f", dark_again)
}

@(test)
lamp_mask_blocks_neither_its_point_light_nor_the_sun :: proc(t: ^testing.T) {
	device: Test_Device
	if !open_test_device(&device) {
		log.info("skipping the lamp mask test: no Vulkan device")
		return
	}
	defer close_test_device(&device)
	state := &device.state
	disable_taa(state)

	normal := geometry.Box {
		center       = {0, 1, 0},
		half_extents = {0.3, 0.3, 0.3},
		color        = {0.9, 0.8, 0.6, 1},
	}
	lamp := normal
	lamp.emissive = 0.01
	floor := geometry.Box {
		center       = {0, -0.5, 0},
		half_extents = {3, 0.5, 3},
		color        = {0.5, 0.5, 0.5, 1},
	}

	testing.expect_value(t, renderer.box_instance_mask(normal), u32(renderer.BOX_INSTANCE_MASK))
	testing.expect_value(t, renderer.box_instance_mask(lamp), u32(renderer.LAMP_INSTANCE_MASK))

	lights := []renderer.Light {
		{position = {0, 1.9, 0}, intensity = 3, color = {1, 1, 1}, range = 8},
	}
	view := renderer.Frame_View {
		camera          = TEST_CAMERA,
		light_direction = {0, 1, 0},
		boxes           = []geometry.Box{floor, normal},
		lights          = lights,
	}
	shadowed := sample_floor(state, view)
	view.boxes = []geometry.Box{floor, lamp}
	lit := sample_floor(state, view)
	testing.expectf(
		t,
		lit > shadowed + 0.2,
		"the lamp box blocked its own point light: %f -> %f",
		shadowed,
		lit,
	)

	view.lights = nil
	view.light_direction = {0, -1, 0}
	view.boxes = []geometry.Box{floor}
	no_lamp := sample_floor(state, view)
	view.boxes = []geometry.Box{floor, lamp}
	with_lamp := sample_floor(state, view)
	testing.expectf(
		t,
		with_lamp < no_lamp - 0.2,
		"the sun did not see the lamp box: %f -> %f",
		no_lamp,
		with_lamp,
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
	view := renderer.Frame_View {
		camera          = TEST_CAMERA,
		light_direction = {0, -1, 0},
		boxes           = []geometry.Box{box},
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

@(private)
disable_taa :: proc(state: ^renderer.Renderer) {
	debug := renderer.renderer_debug(state)
	debug.active = true
	debug.taa = false
	renderer.set_renderer_debug(state, debug)
}

@(private)
draw_scene :: proc(
	state: ^renderer.Renderer,
	view: renderer.Frame_View,
) -> (
	values: []f32,
	width, height: u32,
	ok: bool,
) {
	frame, status := renderer.begin_frame(state, view, {target = .Scene_Color, enabled = true})
	if status != .Ok {
		return nil, 0, 0, false
	}
	if renderer.end_frame(state, frame) != .Ok {
		return nil, 0, 0, false
	}
	pixels, pixel_width, pixel_height, format, read_ok := renderer.read_capture_target(
		state,
		.Scene_Color,
	)
	if !read_ok {
		return nil, 0, 0, false
	}
	decoded := renderer.capture_values(pixels, format, context.temp_allocator)
	return decoded, pixel_width, pixel_height, decoded != nil
}

@(private)
sample_floor :: proc(state: ^renderer.Renderer, view: renderer.Frame_View) -> f32 {
	return sample_point(state, view, {0, 0.001, 0})
}

@(private)
sample_point :: proc(
	state: ^renderer.Renderer,
	view: renderer.Frame_View,
	point: [3]f32,
) -> f32 {
	values, width, height, ok := draw_scene(state, view)
	if !ok {
		return -1
	}
	x, y := scene_pixel(view.camera, width, height, point)
	sum: f32
	count: f32
	for dy in -1 ..= 1 {
		for dx in -1 ..= 1 {
			px := clamp(x + dx, 0, int(width) - 1)
			py := clamp(y + dy, 0, int(height) - 1)
			base := (py * int(width) + px) * 4
			sum += values[base] + values[base + 1] + values[base + 2]
			count += 3
		}
	}
	return sum / count
}

@(private)
mean_luminance :: proc(values: []f32) -> f32 {
	if len(values) == 0 {
		return 0
	}
	sum: f32
	for index := 0; index + 3 < len(values); index += 4 {
		sum += values[index] + values[index + 1] + values[index + 2]
	}
	return sum / f32(len(values) / 4 * 3)
}

// Projects a world point with the same camera math the renderer uses.
@(private)
scene_pixel :: proc(camera: renderer.Camera, width, height: u32, point: [3]f32) -> (x, y: int) {
	aspect := f32(width) / f32(height)
	cos_pitch := math.cos(camera.pitch)
	forward := [3]f32 {
		-math.sin(camera.yaw) * cos_pitch,
		math.sin(camera.pitch),
		-math.cos(camera.yaw) * cos_pitch,
	}
	target := [3]f32 {
		camera.position.x + forward.x,
		camera.position.y + forward.y,
		camera.position.z + forward.z,
	}
	view := renderer.mat4_look_at(camera.position, target, {0, 1, 0})
	projection := renderer.mat4_perspective(
		2 * math.atan(math.tan(camera.fov_x * 0.5) / aspect),
		aspect,
		0.05,
		200.0,
	)
	clip := transform(renderer.mat4_multiply(projection, view), {point.x, point.y, point.z, 1})
	u := clip[0] / clip[3] * 0.5 + 0.5
	v := clip[1] / clip[3] * 0.5 + 0.5
	return int(u * f32(width)), int(v * f32(height))
}

@(private)
transform :: proc(m: renderer.Mat4, v: [4]f32) -> (result: [4]f32) {
	for row in 0 ..< 4 {
		for column in 0 ..< 4 {
			result[row] += m[column * 4 + row] * v[column]
		}
	}
	return
}
