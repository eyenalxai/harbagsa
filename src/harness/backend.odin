#+vet explicit-allocators
package harness

import "core:mem"
import "core:strings"

import "src:appframe"
import "src:bake"
import "src:digest"
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
	ready:        bool,
	ctx:          rawptr,
	acquire:      proc(ctx: rawptr) -> ^renderer.Renderer,
	pick:         proc(
		ctx: rawptr,
		session: ^Session,
		at: [2]i32,
	) -> (renderer.Pick_Hit, renderer.Pick_Failure, string),
	read_capture: proc(
		ctx: rawptr,
		session: ^Session,
		request: Capture_Request,
		slot: int,
	) -> (Capture_Result, string),
	poll:      proc(ctx: rawptr, session: ^Session) -> (platform.Events, bool),
	resize:    proc(ctx: rawptr, width, height: u32) -> bool,
	gpu_times: proc(ctx: rawptr) -> perf.Gpu_Times,
	snapshot:  proc(ctx: rawptr) -> Backend_Snapshot,
	setup:     proc(ctx: rawptr) -> renderer.Setup_Report,
	set_debug: proc(ctx: rawptr, debug: renderer.Renderer_Debug) -> bool,
	get_debug: proc(ctx: rawptr) -> renderer.Renderer_Debug,
	clear_debug: proc(ctx: rawptr),
	publish_bake: proc(ctx: rawptr, artifact: []u8, bake_ms: u32) -> (bool, string),
	refresh_bake: proc(ctx: rawptr, static: bake.Static),
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
	bake_path: string,
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

	renderer_config.bake_path = bake_path
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
		acquire = backend_acquire,
		pick = backend_pick,
		read_capture = backend_capture,
		poll = backend_poll,
		resize = backend_resize,
		gpu_times = backend_gpu_times,
		snapshot = backend_snapshot,
		setup = backend_setup,
		set_debug = backend_set_debug,
		get_debug = backend_get_debug,
		clear_debug = backend_clear_debug,
		publish_bake = backend_publish_bake,
		refresh_bake = backend_refresh_bake,
		shutdown = backend_shutdown,
	}, ""
}

@(private)
backend_acquire :: proc(ctx: rawptr) -> ^renderer.Renderer {
	data := cast(^Backend_Data)ctx
	return &data.renderer
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
backend_publish_bake :: proc(
	ctx: rawptr,
	artifact: []u8,
	bake_ms: u32,
) -> (bool, string) {
	data := cast(^Backend_Data)ctx
	return renderer.publish_bake(&data.renderer, artifact, bake_ms)
}

@(private)
backend_refresh_bake :: proc(ctx: rawptr, static: bake.Static) {
	data := cast(^Backend_Data)ctx
	renderer.refresh_bake(&data.renderer, static)
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

// The offscreen target has no window; the harness sets its extent and marks the
// next frame resized.
@(private)
backend_resize :: proc(ctx: rawptr, width, height: u32) -> bool {
	data := cast(^Backend_Data)ctx
	if data.present || width == 0 || height == 0 {
		return false
	}
	platform.headless_resize(&data.headless, width, height)
	return true
}

// A live window's events still belong to whichever frame runs next, so a
// present session polls before it draws. An offscreen session owns no window.
@(private)
backend_poll :: proc(ctx: rawptr, session: ^Session) -> (platform.Events, bool) {
	data := cast(^Backend_Data)ctx
	if !data.present {
		return {}, true
	}
	events := platform.poll_events(&data.window)
	if events.quit {
		session.quit = true
		return {}, false
	}
	return events, true
}

@(private)
backend_pick :: proc(
	ctx: rawptr,
	session: ^Session,
	at: [2]i32,
) -> (
	renderer.Pick_Hit,
	renderer.Pick_Failure,
	string,
) {
	data := cast(^Backend_Data)ctx
	if session.quit {
		return {}, .Command, format_error("%s", "session is closed")
	}
	session.drawn_alpha = session.default_alpha
	session.drawn_frame = session.frame
	scene := appframe.compose(
		&session.app,
		{
			alpha = session.default_alpha,
			debug_view = session_debug_view(session),
			fx_view = session.view.fx,
			hud = session.view.hud,
		},
		game.SIMULATION_STEP,
	)
	scene.pick_at = at
	return renderer.pick(&data.renderer, scene)
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
