#+vet explicit-allocators
package game

import b3 "libs:box3d"

LIGHT_GIZMO_ANCHOR :: [3]f32{0.0, 6.0, 0.0}
LIGHT_GIZMO_LENGTH :: 4.0
LIGHT_GIZMO_CROSS_SIZE :: 0.4

LIGHT_GIZMO_SELECTED_COLOR :: [4]f32{1.0, 0.8, 0.2, 1.0}
LIGHT_GIZMO_COLOR :: [4]f32{1.0, 0.8, 0.2, 0.5}

collect_light_editor_lines :: proc(dm: ^Debug_Mode, collector: ^Debug_Lines) {
	direction := debug_mode_light_direction(dm)
	anchor := LIGHT_GIZMO_ANCHOR
	end := anchor + direction * LIGHT_GIZMO_LENGTH
	color := LIGHT_GIZMO_COLOR
	if dm.selection == .Light {
		color = LIGHT_GIZMO_SELECTED_COLOR
	}

	append_debug_line(collector, anchor, end, color)
	append_light_cross(collector, end, direction, color)
}

@(private)
append_light_cross :: proc(
	collector: ^Debug_Lines,
	end, direction: [3]f32,
	color: [4]f32,
) {
	side := b3.Perp(direction)
	up := b3.Cross(direction, side)
	append_debug_line(
		collector,
		end - side * LIGHT_GIZMO_CROSS_SIZE,
		end + side * LIGHT_GIZMO_CROSS_SIZE,
		color,
	)
	append_debug_line(
		collector,
		end - up * LIGHT_GIZMO_CROSS_SIZE,
		end + up * LIGHT_GIZMO_CROSS_SIZE,
		color,
	)
}
