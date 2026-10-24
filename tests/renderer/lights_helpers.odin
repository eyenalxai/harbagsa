#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package renderer_test

import "core:math"

import "src:renderer"

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
