#+vet explicit-allocators
package game

import "core:math"

import b3 "libs:box3d"

LIGHT_DRAG_SENSITIVITY :: 0.005
LIGHT_ELEVATION_MIN :: -1.5
LIGHT_ELEVATION_MAX :: -0.05
LIGHT_CLICK_MOTION :: 3.0

debug_edit_light :: proc(dm: ^Debug_Mode, input: Debug_Input) {
	if input.light_pressed {
		if dm.selection == .Light {
			light_deselect(dm)
			return
		}
		dm.selection = .Light
		dm.selected_crate = -1
		dm.dragging = .None
		dm.light_drag_motion = 0.0
		azimuth, elevation := light_angles_from_direction(dm.light_direction)
		dm.light_azimuth = azimuth
		dm.light_elevation = elevation
	}

	if input.primary_pressed && dm.selection == .Light && dm.dragging == .None {
		dm.dragging = .Light
		dm.light_drag_motion = 0.0
		return
	}

	if dm.dragging != .Light {
		return
	}

	if input.captured {
		dx := input.look_delta.x
		dy := input.look_delta.y
		dm.light_azimuth -= dx * LIGHT_DRAG_SENSITIVITY
		dm.light_elevation = clamp(
			dm.light_elevation - dy * LIGHT_DRAG_SENSITIVITY,
			LIGHT_ELEVATION_MIN,
			LIGHT_ELEVATION_MAX,
		)
		dm.light_direction = light_direction_from_angles(dm.light_azimuth, dm.light_elevation)
		dm.light_drag_motion += abs(dx) + abs(dy)
	}

	if input.primary_released {
		if dm.light_drag_motion < LIGHT_CLICK_MOTION {
			light_deselect(dm)
		} else {
			dm.dragging = .None
			dm.light_drag_motion = 0.0
		}
	}
}

light_angles_from_direction :: proc(direction: [3]f32) -> (azimuth, elevation: f32) {
	normalized := b3.Normalize(direction)
	elevation = math.asin(clamp(normalized.y, -1.0, 1.0))
	azimuth = math.atan2(normalized.x, normalized.z)
	return azimuth, elevation
}

light_direction_from_angles :: proc(azimuth, elevation: f32) -> [3]f32 {
	return b3.Normalize(
		{
			math.cos(elevation) * math.sin(azimuth),
			math.sin(elevation),
			math.cos(elevation) * math.cos(azimuth),
		},
	)
}

@(private)
light_deselect :: proc(dm: ^Debug_Mode) {
	dm.selection = .None
	dm.dragging = .None
	dm.light_drag_motion = 0.0
}
