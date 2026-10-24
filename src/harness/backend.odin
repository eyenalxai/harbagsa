#+vet explicit-allocators
package harness

import "core:mem"
import "core:strings"

import "src:digest"
import "src:frame"
import "src:perf"
import "src:platform"
import "src:renderer"

Backend_Snapshot :: struct {
	report:     renderer.Renderer_Report,
	digest:     digest.FNV,
	has_digest: bool,
}

Backend :: struct {
	ready:    bool,
	ctx:      rawptr,
	render:   proc(
		ctx: rawptr,
		session: ^Session,
		request: Capture_Request,
	) -> (Capture_Result, string),
	gpu_times: proc(ctx: rawptr) -> perf.Gpu_Times,
	snapshot:  proc(ctx: rawptr) -> Backend_Snapshot,
	setup:     proc(ctx: rawptr) -> renderer.Setup_Report,
	set_debug: proc(ctx: rawptr, debug: renderer.TAA_Debug) -> bool,
	get_debug: proc(ctx: rawptr) -> renderer.TAA_Debug,
	clear_debug: proc(ctx: rawptr),
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
		snapshot = backend_snapshot,
		setup = backend_setup,
		set_debug = backend_set_debug,
		get_debug = backend_get_debug,
		clear_debug = backend_clear_debug,
		shutdown = backend_shutdown,
	}, ""
}

@(private)
backend_set_debug :: proc(ctx: rawptr, debug: renderer.TAA_Debug) -> bool {
	data := cast(^Backend_Data)ctx
	return renderer.set_taa_debug(&data.renderer, debug)
}

@(private)
backend_get_debug :: proc(ctx: rawptr) -> renderer.TAA_Debug {
	data := cast(^Backend_Data)ctx
	return renderer.taa_debug(&data.renderer)
}

@(private)
backend_clear_debug :: proc(ctx: rawptr) {
	data := cast(^Backend_Data)ctx
	renderer.clear_taa_debug(&data.renderer)
}

@(private)
backend_snapshot :: proc(ctx: rawptr) -> Backend_Snapshot {
	data := cast(^Backend_Data)ctx
	value, has := renderer.last_render_digest(&data.renderer)
	return {report = renderer.renderer_report(&data.renderer), digest = value, has_digest = has}
}

@(private)
backend_setup :: proc(ctx: rawptr) -> renderer.Setup_Report {
	data := cast(^Backend_Data)ctx
	return renderer.setup_report(&data.renderer)
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
	request: Capture_Request,
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
		alpha      = request.alpha,
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
	capture_request := renderer.Capture_Request {
		target  = request.target,
		enabled = request.enabled,
	}
	status: renderer.Frame_Status
	for _ in 0 ..< 2 {
		status = frame.draw(&data.renderer, scene, capture_request)
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
	if !request.enabled {
		return {}, ""
	}

	return backend_capture(data, session, request)
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
