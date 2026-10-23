#+vet explicit-allocators
package harness

import "core:mem"
import "core:strings"

import "src:frame"
import "src:platform"
import "src:renderer"

Backend_Data :: struct {
	window:    platform.Window,
	headless:  platform.Headless,
	renderer:  renderer.Renderer,
	present:   bool,
	frames_dir: string,
	allocator: mem.Allocator,
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
		shutdown = backend_shutdown,
	}, ""
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
			return {}, "render failed"
		}
		return {}, "frame skipped"
	}
	if !capture {
		return {}, ""
	}

	pixels, width, height, ok := renderer.read_capture(&data.renderer)
	if !ok {
		return {}, "capture readback failed"
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
	delete(data.frames_dir, data.allocator)
	free(data, data.allocator)
}

backend_destroy :: proc(backend: ^Backend) {
	if backend.ready && backend.shutdown != nil {
		backend.shutdown(backend.ctx)
	}
	backend^ = {}
}
