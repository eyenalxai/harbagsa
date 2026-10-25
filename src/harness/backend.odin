#+vet explicit-allocators
package harness

import "core:mem"
import "core:strings"

import "src:digest"
import "src:frame"
import "src:game"
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
		requests: []Capture_Request,
	) -> ([]Capture_Result, string),
	gpu_times: proc(ctx: rawptr) -> perf.Gpu_Times,
	snapshot:  proc(ctx: rawptr) -> Backend_Snapshot,
	setup:     proc(ctx: rawptr) -> renderer.Setup_Report,
	set_debug: proc(ctx: rawptr, debug: renderer.Renderer_Debug) -> bool,
	get_debug: proc(ctx: rawptr) -> renderer.Renderer_Debug,
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
			return {}, format_error("%s", "platform init failed")
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
			return {}, format_error("%s", "headless Vulkan loader init failed")
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
		return {}, format_error("%s", "renderer init failed")
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
backend_set_debug :: proc(ctx: rawptr, debug: renderer.Renderer_Debug) -> bool {
	data := cast(^Backend_Data)ctx
	return renderer.set_renderer_debug(&data.renderer, debug)
}

@(private)
backend_get_debug :: proc(ctx: rawptr) -> renderer.Renderer_Debug {
	data := cast(^Backend_Data)ctx
	return renderer.renderer_debug(&data.renderer)
}

@(private)
backend_clear_debug :: proc(ctx: rawptr) {
	data := cast(^Backend_Data)ctx
	renderer.clear_renderer_debug(&data.renderer)
}

@(private)
backend_snapshot :: proc(ctx: rawptr) -> Backend_Snapshot {
	data := cast(^Backend_Data)ctx
	return {
		report = renderer.renderer_report(&data.renderer),
		digest = data.renderer.render_digest,
		has_digest = data.renderer.has_render_digest,
	}
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
	requests: []Capture_Request,
) -> (
	[]Capture_Result,
	string,
) {
	data := cast(^Backend_Data)ctx
	if data.present {
		events := platform.poll_events(&data.window)
		if events.quit {
			session.quit = true
			return nil, ""
		}
		if events.resized {
			renderer.notify_resize(&data.renderer)
		}
	}

	alpha := session.alpha
	if len(requests) > 0 {
		alpha = requests[0].alpha
	}
	options := frame.Options {
		alpha         = alpha,
		delta_seconds = game.SIMULATION_STEP,
		debug_view    = session.view.debug,
		captured      = !session.view.hint,
		hud           = session.view.hud,
		perf          = session.view.perf,
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
		session.scratch,
	)
	perf.mark(&session.perf, .Build)
	if len(requests) > 0 {
		if !renderer.text_atlas_sync(&data.renderer, session.sim.settings.type_weight) {
			return nil, format_error("text atlas sync failed")
		}
		if !renderer.text_atlas_wait(&data.renderer) {
			return nil, format_error("text atlas did not settle")
		}
	}
	data.renderer.recorder = &session.perf.recorder
	targets: renderer.Capture_Targets
	for request in requests {
		targets |= {request.target}
	}
	capture_request := renderer.Frame_Capture{targets = targets}
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
			return nil, format_error("render failed")
		}
		return nil, format_error("frame skipped")
	}
	if len(requests) == 0 {
		return nil, ""
	}

	slot_of: [renderer.Capture_Target]int
	for target in renderer.Capture_Target {
		slot_of[target] = -1
	}
	slot := 0
	for target in renderer.Capture_Target {
		if target in targets {
			slot_of[target] = slot
			slot += 1
		}
	}
	results := make([dynamic]Capture_Result, 0, len(requests), context.allocator)
	for request in requests {
		result, error := backend_capture(data, session, request, slot_of[request.target])
		if error != "" {
			for &written in results {
				capture_result_destroy(&written, data.allocator)
			}
			delete(results)
			return nil, error
		}
		append(&results, result)
	}
	return results[:], ""
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
