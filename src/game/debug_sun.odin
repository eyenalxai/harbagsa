#+vet explicit-allocators
#+vet !unused-procedures // the agent harness and tests call this API; the game binary does not
package game

import "core:math"

import b3 "libs:box3d"

SUN_DOME_CENTER :: [3]f32{0.0, 0.0, 0.0}
SUN_DOME_RADIUS :: 50.0
SUN_DOME_MIN_HEIGHT :: 2.5
SUN_AIM_DISTANCE :: 50.0
SUN_AIM_EPSILON :: 0.0001

DEFAULT_SUN_DIRECTION :: [3]f32{-0.45, -1.0, -0.35}

// The default direction at the dome radius, so a fresh sun sits on the dome and
// matches the old default light.
DEFAULT_SUN_POSITION :: [3]f32{19.5467, 43.4372, 15.2030}

@(private)
edit_sun_enter :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> Edit_Result {
	if dm.sun.active {
		return edit_ok()
	}
	palette_close(&dm.palette)
	debug_placement_cancel(dm)
	debug_mode_end_drag(dm)
	dm.sun.saved_position = dm.sun.position
	dm.sun.active = true
	debug_sun_refresh(dm, sim)
	return edit_ok()
}

// Leaving the mode keeps the live position; the commit is just the click that
// ends it.
@(private)
edit_sun_exit :: proc(dm: ^Debug_Mode) -> Edit_Result {
	if !dm.sun.active {
		return edit_no_change()
	}
	dm.sun.active = false
	return edit_ok()
}

@(private)
edit_sun_cancel :: proc(dm: ^Debug_Mode) -> Edit_Result {
	if !dm.sun.active {
		return edit_no_change()
	}
	debug_sun_cancel(dm)
	return edit_ok()
}

@(private)
debug_sun_cancel :: proc(dm: ^Debug_Mode) {
	if !dm.sun.active {
		return
	}
	dm.sun.position = dm.sun.saved_position
	dm.sun.active = false
}

@(private)
edit_sun_toggle :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> Edit_Result {
	if dm.sun.active {
		return edit_sun_exit(dm)
	}
	return edit_sun_enter(dm, sim)
}

@(private)
edit_sun_set_position :: proc(dm: ^Debug_Mode, position: [3]f32) -> Edit_Result {
	sun_position_set(dm, position)
	return edit_ok()
}

// The keyboard and the harness both go through here: a position is projected
// onto the dome and clamped above the floor, so a raw position cannot leave the
// sun under the arena.
sun_position_set :: proc(dm: ^Debug_Mode, position: [3]f32) {
	dm.sun.position = sun_dome_point(position)
}

debug_sun_reset :: proc(dm: ^Debug_Mode) {
	dm.sun = {position = DEFAULT_SUN_POSITION}
}

@(private)
debug_sun_refresh :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	if !dm.sun.active || sim == nil || !simulation_is_valid(sim) {
		return
	}
	dm.sun.position = sun_dome_point(debug_aim_point(dm, sim, SUN_AIM_DISTANCE))
}

sun_dome_point :: proc(aim: [3]f32) -> [3]f32 {
	offset := aim - SUN_DOME_CENTER
	length := b3.Length(offset)
	if length <= SUN_AIM_EPSILON {
		return DEFAULT_SUN_POSITION
	}
	point := SUN_DOME_CENTER + offset * (SUN_DOME_RADIUS / length)
	point.y = max(point.y, SUN_DOME_CENTER.y + SUN_DOME_MIN_HEIGHT)
	return point
}

sun_direction_from_position :: proc(position: [3]f32) -> [3]f32 {
	offset := SUN_DOME_CENTER - position
	length := b3.Length(offset)
	if length <= SUN_AIM_EPSILON {
		return b3.Normalize(DEFAULT_SUN_DIRECTION)
	}
	return offset * (1.0 / length)
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
