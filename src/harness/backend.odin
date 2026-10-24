#+vet explicit-allocators
package harness

import "core:mem"
import "core:strings"

import "src:frame"
import "src:perf"
import "src:platform"
import "src:renderer"

Backend :: struct {
	ready:    bool,
	ctx:      rawptr,
	render:   proc(
		ctx: rawptr,
		session: ^Session,
		capture: bool,
		name: string,
		alpha: f32,
	) -> (Capture_Result, string),
	gpu_times: proc(ctx: rawptr) -> perf.Gpu_Times,
	shutdown:  proc(ctx: rawptr),
}

Backend_Data :: struct {
	window:          platform.Window,
	headless:        platform.Headless,
	renderer:        renderer.Renderer,
	present:         bool,
	frames_dir:      string,
	allocator:       mem.Allocator,
	previous_pixels: []u8,
	previous_width:  u32,
	previous_height: u32,
}

backend_create :: proc(
	width, height: u32,
	present: bool,
	frames_dir: string,
	allocator: mem.Allocator,
) -> (
	Backend,
	string,
) {
	data := new(Backend_Data, allocator)
	data.present = present
	data.allocator = allocator
	data.frames_dir = strings.clone(frames_dir, allocator)

	renderer_config: renderer.Config
	if present {
		window, platform_error := platform.init(
			"harbagsa-agent",
			i32(width),
			i32(height),
		)
		if platform_error != .None {
			delete(data.frames_dir, allocator)
			free(data, allocator)
			return {}, "platform init failed"
		}
		data.window = window
		renderer_config = {
			platform = platform.renderer_platform(&data.window),
			target   = .Swapchain,
			width    = width,
			height   = height,
		}
	} else {
		if !platform.headless_init(&data.headless, width, height) {
			delete(data.frames_dir, allocator)
			free(data, allocator)
			return {}, "headless Vulkan loader init failed"
		}
		renderer_config = {
			platform = platform.headless_platform(&data.headless),
			target   = .Offscreen,
			width    = width,
			height   = height,
		}
	}

	state, renderer_error := renderer.init(renderer_config, allocator)
	if renderer_error != .None {
		if present {
			platform.deinit(&data.window)
		} else {
			platform.headless_deinit(&data.headless)
		}
		delete(data.frames_dir, allocator)
		free(data, allocator)
		return {}, "renderer init failed"
	}
	data.renderer = state
	return {
		ready = true,
		ctx = data,
		render = backend_render,
		gpu_times = backend_gpu_times,
		shutdown = backend_shutdown,
	}, ""
}

@(private)
backend_gpu_times :: proc(ctx: rawptr) -> perf.Gpu_Times {
	data := cast(^Backend_Data)ctx
	return renderer.gpu_times(&data.renderer)
}

@(private)
backend_render :: proc(
	ctx: rawptr,
	session: ^Session,
	capture: bool,
	name: string,
	alpha: f32,
) -> (
	Capture_Result,
	string,
) {
	data := cast(^Backend_Data)ctx
	if data.present {
		events := platform.poll_events(&data.window)
		if events.quit {
			session.quit = true
			return {}, ""
		}
		if events.resized {
			renderer.notify_resize(&data.renderer)
		}
	}

	options := frame.Options {
		alpha      = alpha,
		debug_view = session.view.debug,
		captured   = !session.view.hint,
		hud        = session.view.hud,
	}
	session.hud.perf.visible = session.view.perf
	if session.hud.perf.visible {
		session.hud.perf.stats = perf.stats(&session.perf)
	}
	camera_override: ^renderer.Camera
	if session.has_camera_override {
		camera_override = &session.camera_override
	}
	scene := frame.build(
		&session.sim,
		&session.debug,
		options,
		camera_override,
		&session.hud,
		&session.scratch,
	)
	perf.mark(&session.perf, .Build)
	data.renderer.recorder = &session.perf.recorder
	status: renderer.Frame_Status
	for _ in 0 ..< 2 {
		status = frame.draw(&data.renderer, scene, capture)
		if status == .Ok {
			break
		}
		if status == .Fatal {
			break
		}
	}
	if status != .Ok {
		if status == .Fatal {
			return {}, format_error("render failed")
		}
		return {}, format_error("frame skipped")
	}
	if !capture {
		return {}, ""
	}

	pixels, width, height, ok := renderer.read_capture(&data.renderer)
	if !ok {
		return {}, format_error("capture readback failed")
	}
	delta: Capture_Delta
	if data.previous_pixels != nil &&
	   data.previous_width == width &&
	   data.previous_height == height &&
	   len(data.previous_pixels) == len(pixels) {
		delta = capture_delta(data.previous_pixels, pixels)
	}
	result, write_error := capture_write_png(
		data.frames_dir,
		name,
		session.frame,
		width,
		height,
		pixels,
		data.allocator,
	)
	if write_error != "" {
		return {}, write_error
	}
	result.delta_mean = delta.mean
	result.delta_max = delta.max
	result.delta_over_16 = delta.over_16
	if len(data.previous_pixels) != len(pixels) {
		delete(data.previous_pixels, data.allocator)
		data.previous_pixels = make([]u8, len(pixels), data.allocator)
	}
	copy(data.previous_pixels, pixels)
	data.previous_width = width
	data.previous_height = height
	return result, ""
}

@(private)
backend_shutdown :: proc(ctx: rawptr) {
	data := cast(^Backend_Data)ctx
	renderer.deinit(&data.renderer)
	if data.present {
		platform.deinit(&data.window)
	} else {
		platform.headless_deinit(&data.headless)
	}
	delete(data.previous_pixels, data.allocator)
	delete(data.frames_dir, data.allocator)
	free(data, data.allocator)
}

backend_destroy :: proc(backend: ^Backend) {
	if backend.ready && backend.shutdown != nil {
		backend.shutdown(backend.ctx)
	}
	backend^ = {}
}
