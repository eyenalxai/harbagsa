#+vet explicit-allocators
package game

import "core:math"

import b3 "libs:box3d"

SUN_GIZMO_RING_RADIUS :: 2.5
SUN_GIZMO_RING_SEGMENTS :: 24
SUN_GIZMO_DASH_LENGTH :: 1.5
SUN_GIZMO_DASH_GAP :: 1.0

SUN_GIZMO_COLOR :: [4]f32{1.0, 0.8, 0.2, 1.0}

collect_sun_editor_lines :: proc(dm: ^Debug_Mode, collector: ^Debug_Lines) {
	if !dm.sun.active {
		return
	}
	position := dm.sun.position
	to_sun := position - SUN_DOME_CENTER
	length := b3.Length(to_sun)
	if length <= SUN_AIM_EPSILON {
		return
	}

	normal := to_sun * (1.0 / length)
	side := b3.Perp(normal)
	up := b3.Cross(normal, side)
	append_sun_ring(collector, position, side, up, SUN_GIZMO_COLOR)
	append_sun_cross(collector, position, side, up, SUN_GIZMO_COLOR)
	append_sun_dashed_line(collector, SUN_DOME_CENTER, position, SUN_GIZMO_COLOR)
}

@(private)
append_sun_ring :: proc(
	collector: ^Debug_Lines,
	position, side, up: [3]f32,
	color: [4]f32,
) {
	step := 2.0 * math.PI / f32(SUN_GIZMO_RING_SEGMENTS)
	for index in 0 ..< SUN_GIZMO_RING_SEGMENTS {
		angle := f32(index) * step
		next := angle + step
		from := position +
			side * (math.cos(angle) * SUN_GIZMO_RING_RADIUS) +
			up * (math.sin(angle) * SUN_GIZMO_RING_RADIUS)
		to := position +
			side * (math.cos(next) * SUN_GIZMO_RING_RADIUS) +
			up * (math.sin(next) * SUN_GIZMO_RING_RADIUS)
		append_debug_line(collector, from, to, color)
	}
}

@(private)
append_sun_cross :: proc(
	collector: ^Debug_Lines,
	position, side, up: [3]f32,
	color: [4]f32,
) {
	arm: f32 = SUN_GIZMO_RING_RADIUS
	append_debug_line(collector, position - side * arm, position + side * arm, color)
	append_debug_line(collector, position - up * arm, position + up * arm, color)
}

@(private)
append_sun_dashed_line :: proc(
	collector: ^Debug_Lines,
	from, to: [3]f32,
	color: [4]f32,
) {
	offset := to - from
	length := b3.Length(offset)
	if length <= SUN_AIM_EPSILON {
		return
	}
	direction := offset * (1.0 / length)
	cursor: f32 = 0.0
	for cursor < length {
		start := from + direction * cursor
		end := from + direction * min(cursor + SUN_GIZMO_DASH_LENGTH, length)
		append_debug_line(collector, start, end, color)
		cursor += SUN_GIZMO_DASH_LENGTH + SUN_GIZMO_DASH_GAP
	}
}
