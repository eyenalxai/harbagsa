#+vet explicit-allocators
package game

import b3 "libs:box3d"
import "src:geometry"

DEBUG_LINE_CAPACITY :: 4096

Debug_Lines :: struct {
	lines: [DEBUG_LINE_CAPACITY]geometry.Line,
	count: int,
}

collect_world_lines :: proc(sim: ^Simulation, collector: ^Debug_Lines) {
	collector.count = 0
	if !simulation_is_valid(sim) {
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

collect_editor_lines :: proc(dm: ^Debug_Mode, sim: ^Simulation, collector: ^Debug_Lines) {
	collect_object_editor_lines(dm, sim, collector)
	collect_sun_editor_lines(dm, collector)
}

append_debug_line :: proc "contextless" (collector: ^Debug_Lines, from, to: [3]f32, color: [4]f32) {
	if collector.count >= len(collector.lines) {
		return
	}
	collector.lines[collector.count] = {from = from, to = to, color = color}
	collector.count += 1
}

append_box_edges :: proc "contextless" (collector: ^Debug_Lines, corners: [8][3]f32, color: [4]f32) {
	edges := [12][2]int {
		{0, 1}, {1, 2}, {2, 3}, {3, 0},
		{4, 5}, {5, 6}, {6, 7}, {7, 4},
		{0, 4}, {1, 5}, {2, 6}, {3, 7},
	}
	for edge in edges {
		append_debug_line(collector, corners[edge.x], corners[edge.y], color)
	}
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

// Draws bounds and contacts, not exact shape outlines.
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
	append_box_edges(collector, corners, line_color)
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
