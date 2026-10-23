#+vet explicit-allocators
package main

import "core:log"
import "core:math"
import "core:os"
import "core:time"

import b3 "libs:box3d"
import "src:game"
import "src:geometry"
import "src:platform"
import "src:renderer"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

PLAYER_FOV_X :: f32(90.0 * math.PI / 180.0)
MAX_FRAME_DELTA :: f32(0.1)
MAX_STEPS_PER_FRAME :: 8

DEBUG_LINE_CAPACITY :: 4096

Debug_Lines :: struct {
	lines: [DEBUG_LINE_CAPACITY]geometry.Line,
	count: int,
}

main :: proc() {
	logger := log.create_console_logger(lowest = .Info, allocator = context.allocator)
	context.logger = logger

	ok := run()
	log.destroy_console_logger(logger, allocator = context.allocator)
	if !ok {
		os.exit(1)
	}
}

run :: proc() -> bool {
	window, platform_error := platform.init("harbagsa", WINDOW_WIDTH, WINDOW_HEIGHT)
	if platform_error != .None {
		log.errorf("harbagsa: platform init failed: %v", platform_error)
		return false
	}
	defer platform.deinit(&window)

	state, renderer_error := renderer.init(&window, context.allocator)
	if renderer_error != .None {
		log.errorf("harbagsa: renderer init failed: %v", renderer_error)
		return false
	}
	defer renderer.deinit(&state)

	sim := game.simulation_create()
	if !game.simulation_is_valid(&sim) {
		log.error("harbagsa: simulation init failed")
		return false
	}
	defer game.simulation_destroy(&sim)

	accumulator: f32 = 0
	jump_latched := false
	reset_latched := false
	debug_view := false
	debug_lines: Debug_Lines
	last_time := time.now()

	for {
		events := platform.poll_events(&window)
		if events.quit {
			return true
		}
		if events.resized {
			renderer.notify_resize(&state)
		}
		if events.debug_pressed {
			debug_view = !debug_view
		}

		width, height := platform.pixel_size(&window)
		if platform.is_minimized(&window) || width == 0 || height == 0 {
			// Do not spin while minimized or while the window has no drawable
			// area. Block until an event or a short timeout, then try again.
			waited := platform.wait_events(&window, 100)
			if waited.quit {
				return true
			}
			if waited.resized {
				renderer.notify_resize(&state)
			}
			// Drop the time spent waiting so the first restored frame does
			// not step the simulation for the whole pause.
			last_time = time.now()
			continue
		}

		now := time.now()
		delta := f32(time.duration_seconds(time.diff(last_time, now)))
		last_time = now
		delta = clamp(delta, 0, MAX_FRAME_DELTA)

		// Look and jump are frame edges. Look applies even when this frame
		// runs no fixed step; jump is consumed by the first step. Both are
		// player input, so both are ignored while the cursor is free.
		if events.captured {
			game.simulation_look(&sim, events.look_delta)
		} else {
			jump_latched = false
		}
		if events.captured && events.jump_pressed {
			jump_latched = true
		}
		if events.reset_pressed {
			jump_latched = false
			reset_latched = true
		}

		accumulator += delta
		steps := 0
		for accumulator >= game.SIMULATION_STEP && steps < MAX_STEPS_PER_FRAME {
			game.simulation_step(
				&sim,
				game.Input_Snapshot {
					move_forward = events.move_forward,
					move_right = events.move_right,
					jump_pressed = jump_latched,
					reset_pressed = reset_latched,
				},
				game.SIMULATION_STEP,
			)
			jump_latched = false
			reset_latched = false
			accumulator -= game.SIMULATION_STEP
			steps += 1
		}
		if steps == MAX_STEPS_PER_FRAME && accumulator >= game.SIMULATION_STEP {
			// A long stall must not build a backlog that never drains.
			accumulator = 0
		}

		snapshot := game.simulation_snapshot(&sim)
		alpha := clamp(accumulator / game.SIMULATION_STEP, 0, 1)
		eye := snapshot.previous_eye_position +
		       (snapshot.eye_position - snapshot.previous_eye_position) * alpha
		camera := renderer.Camera {
			position = eye,
			yaw      = snapshot.yaw,
			pitch    = snapshot.pitch,
			fov_x    = PLAYER_FOV_X,
		}

		boxes: [game.ARENA_BOX_COUNT]geometry.Box
		for box, index in game.arena_static_boxes() {
			boxes[index] = box
		}
		for box, index in game.arena_crates() {
			draw_index := game.ARENA_STATIC_BOX_COUNT + index
			boxes[draw_index] = box
			boxes[draw_index].center = game.simulation_crate_position(&sim, index)
			rotation := game.simulation_crate_rotation(&sim, index)
			boxes[draw_index].rotation = {rotation.x, rotation.y, rotation.z, rotation.w}
		}

		debug_lines.count = 0
		if debug_view {
			collect_debug_lines(&sim, &debug_lines)
		}

		hud := renderer.HUD_State {
			speed    = math.sqrt(
				snapshot.velocity.x * snapshot.velocity.x +
				snapshot.velocity.z * snapshot.velocity.z,
			),
			grounded = snapshot.grounded,
			position = {snapshot.position.x, snapshot.position.y, snapshot.position.z},
			captured = events.captured,
		}

		frame, begin_status := renderer.begin_frame(
			&state,
			camera,
			boxes[:],
			debug_lines.lines[:debug_lines.count],
			hud,
		)
		switch begin_status {
		case .Ok:
		case .Skipped:
			continue
		case .Fatal:
			return false
		}

		switch renderer.end_frame(&state, frame) {
		case .Ok:
		case .Skipped:
			// The swapchain is out of date. The next frame recreates it.
		case .Fatal:
			return false
		}
	}
}

// collect_debug_lines asks Box3D to report the physics world as line segments.
// The pass draws each shape's fat AABB and each contact point; it does not draw
// the full shape outline, so the capsule and hull silhouettes are approximated
// by their bounds.
collect_debug_lines :: proc(sim: ^game.Simulation, collector: ^Debug_Lines) {
	collector.count = 0
	if !game.simulation_is_valid(sim) {
		return
	}

	draw := b3.DefaultDebugDraw()
	draw.ctx = collector
	draw.drawShapes = false
	draw.drawBounds = true
	draw.drawContacts = true
	draw.DrawBoundsFcn = debug_draw_bounds
	draw.DrawSegmentFcn = debug_draw_segment
	draw.DrawPointFcn = debug_draw_point
	b3.World_Draw(sim.world_id, &draw, max(u64))
}

debug_draw_bounds :: proc "c" (aabb: b3.AABB, color: b3.HexColor, ctx: rawptr) {
	collector := cast(^Debug_Lines)ctx
	line_color := debug_color(color, 0.85)
	lower := aabb.lowerBound
	upper := aabb.upperBound

	corners := [8][3]f32 {
		{lower.x, lower.y, lower.z},
		{upper.x, lower.y, lower.z},
		{upper.x, upper.y, lower.z},
		{lower.x, upper.y, lower.z},
		{lower.x, lower.y, upper.z},
		{upper.x, lower.y, upper.z},
		{upper.x, upper.y, upper.z},
		{lower.x, upper.y, upper.z},
	}
	edges := [12][2]int {
		{0, 1}, {1, 2}, {2, 3}, {3, 0},
		{4, 5}, {5, 6}, {6, 7}, {7, 4},
		{0, 4}, {1, 5}, {2, 6}, {3, 7},
	}
	for edge in edges {
		append_debug_line(collector, corners[edge.x], corners[edge.y], line_color)
	}
}

debug_draw_segment :: proc "c" (from, to: b3.Pos, color: b3.HexColor, ctx: rawptr) {
	collector := cast(^Debug_Lines)ctx
	append_debug_line(
		collector,
		{from.x, from.y, from.z},
		{to.x, to.y, to.z},
		debug_color(color, 1.0),
	)
}

debug_draw_point :: proc "c" (point: b3.Pos, size: f32, color: b3.HexColor, ctx: rawptr) {
	collector := cast(^Debug_Lines)ctx
	center := [3]f32{point.x, point.y, point.z}
	half := clamp(size * 0.008, 0.06, 0.20)
	line_color := debug_color(color, 1.0)

	append_debug_line(collector, center - {half, 0, 0}, center + {half, 0, 0}, line_color)
	append_debug_line(collector, center - {0, half, 0}, center + {0, half, 0}, line_color)
	append_debug_line(collector, center - {0, 0, half}, center + {0, 0, half}, line_color)
}

append_debug_line :: proc "contextless" (collector: ^Debug_Lines, from, to: [3]f32, color: [4]f32) {
	if collector.count >= len(collector.lines) {
		return
	}
	collector.lines[collector.count] = {from = from, to = to, color = color}
	collector.count += 1
}

debug_color :: proc "contextless" (color: b3.HexColor, alpha: f32) -> [4]f32 {
	rgb := u32(color) & 0x00FFFFFF
	return {
		f32((rgb >> 16) & 0xFF) / 255.0,
		f32((rgb >> 8) & 0xFF) / 255.0,
		f32(rgb & 0xFF) / 255.0,
		alpha,
	}
}
