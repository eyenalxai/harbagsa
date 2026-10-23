#+vet explicit-allocators
package game

import "core:math"

import b3 "libs:box3d"

SUN_DRAG_SENSITIVITY :: 0.005
SUN_ELEVATION_MIN :: -1.5
SUN_ELEVATION_MAX :: -0.05
SUN_CLICK_MOTION :: 3.0

debug_edit_sun :: proc(dm: ^Debug_Mode, input: Debug_Input) {
	if input.sun_pressed {
		if dm.selection == .Sun {
			debug_mode_clear_selection(dm)
			return
		}
		dm.selection = .Sun
		dm.selected_crate = -1
		debug_mode_end_drag(dm)
		azimuth, elevation := sun_angles_from_direction(dm.sun_direction)
		dm.sun_azimuth = azimuth
		dm.sun_elevation = elevation
	}

	if input.primary_pressed && dm.selection == .Sun && dm.dragging == .None {
		dm.dragging = .Sun
		dm.sun_drag_dx = 0.0
		dm.sun_drag_dy = 0.0
	}

	if dm.dragging != .Sun {
		return
	}

	if input.captured {
		dx := input.look_delta.x
		dy := input.look_delta.y
		dm.sun_drag_dx += dx
		dm.sun_drag_dy += dy
		dm.sun_azimuth -= dx * SUN_DRAG_SENSITIVITY
		dm.sun_elevation = clamp(
			dm.sun_elevation - dy * SUN_DRAG_SENSITIVITY,
			SUN_ELEVATION_MIN,
			SUN_ELEVATION_MAX,
		)
		dm.sun_direction = sun_direction_from_angles(dm.sun_azimuth, dm.sun_elevation)
	}

	if input.primary_released {
		motion := math.sqrt(dm.sun_drag_dx * dm.sun_drag_dx + dm.sun_drag_dy * dm.sun_drag_dy)
		if motion < SUN_CLICK_MOTION {
			debug_mode_clear_selection(dm)
		} else {
			debug_mode_end_drag(dm)
		}
	}
}

sun_angles_from_direction :: proc(direction: [3]f32) -> (azimuth, elevation: f32) {
	normalized := b3.Normalize(direction)
	elevation = math.asin(clamp(normalized.y, -1.0, 1.0))
	azimuth = math.atan2(normalized.x, normalized.z)
	return azimuth, elevation
}

sun_direction_from_angles :: proc(azimuth, elevation: f32) -> [3]f32 {
	return b3.Normalize(
		{
			math.cos(elevation) * math.sin(azimuth),
			math.sin(elevation),
			math.cos(elevation) * math.cos(azimuth),
		},
	)
}
