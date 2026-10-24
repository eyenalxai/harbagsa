#+vet explicit-allocators
package game

import "core:math"

import b3 "libs:box3d"

SUN_DRAG_SENSITIVITY :: 0.005
SUN_ELEVATION_MIN :: 0.05
SUN_ELEVATION_MAX :: 1.5
SUN_CLICK_MOTION :: 3.0

debug_edit_sun :: proc(dm: ^Debug_Mode, input: Debug_Input) {
	if dm.palette.open || dm.placement.armed {
		return
	}
	if input.sun_pressed {
		if dm.selection == .Sun {
			debug_mode_clear_selection(dm)
			return
		}
		dm.selection = .Sun
		dm.selected_object_id = INVALID_OBJECT_ID
		debug_mode_end_drag(dm)
		dm.sun_azimuth, dm.sun_elevation = debug_mode_sun_angles(dm)
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
		dm.sun_direction = light_direction_from_sun(
			sun_direction_from_angles(dm.sun_azimuth, dm.sun_elevation),
		)
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

// Sun angles in the sky: azimuth from +z toward +x, elevation above the
// horizon. The renderer instead consumes the light travel direction, which
// points the other way.
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

sun_direction_from_light :: proc(light_direction: [3]f32) -> [3]f32 {
	return {-light_direction.x, -light_direction.y, -light_direction.z}
}

light_direction_from_sun :: proc(sun_direction: [3]f32) -> [3]f32 {
	return sun_direction_from_light(sun_direction)
}
