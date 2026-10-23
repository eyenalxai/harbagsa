#+vet explicit-allocators
package game

import b3 "libs:box3d"

SUN_GIZMO_ANCHOR :: [3]f32{0.0, 6.0, 0.0}
SUN_GIZMO_LENGTH :: 4.0
SUN_GIZMO_HEAD_SIZE :: 0.6

SUN_GIZMO_SELECTED_COLOR :: [4]f32{1.0, 0.8, 0.2, 1.0}
SUN_GIZMO_COLOR :: [4]f32{1.0, 0.8, 0.2, 0.5}

collect_sun_editor_lines :: proc(dm: ^Debug_Mode, collector: ^Debug_Lines) {
	direction := debug_mode_sun_direction(dm)
	anchor := SUN_GIZMO_ANCHOR
	end := anchor + direction * SUN_GIZMO_LENGTH
	color := SUN_GIZMO_COLOR
	if dm.selection == .Sun {
		color = SUN_GIZMO_SELECTED_COLOR
	}

	append_debug_line(collector, anchor, end, color)
	append_sun_head(collector, end, direction, color)
}

@(private)
append_sun_head :: proc(
	collector: ^Debug_Lines,
	end, direction: [3]f32,
	color: [4]f32,
) {
	side := b3.Perp(direction)
	up := b3.Cross(direction, side)
	back := end - direction * SUN_GIZMO_HEAD_SIZE
	half: f32 = SUN_GIZMO_HEAD_SIZE * 0.5
	append_debug_line(collector, end, back + side * half, color)
	append_debug_line(collector, end, back - side * half, color)
	append_debug_line(collector, end, back + up * half, color)
	append_debug_line(collector, end, back - up * half, color)
}
