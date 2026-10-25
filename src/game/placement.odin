#+vet explicit-allocators
#+vet !unused-procedures // the agent harness and tests call this API; the game binary does not
package game

import "core:math"

import b3 "libs:box3d"
import "src:geometry"

PLACEMENT_HEIGHT_STEP :: 0.25
PLACEMENT_HEIGHT_STEP_LARGE :: 1.0
PLACEMENT_YAW_STEP :: 15.0
PLACEMENT_YAW_STEP_LARGE :: 45.0
PLACEMENT_SNAP_STEP :: 0.25
PLACEMENT_FALLBACK_DISTANCE :: 3.0

Placement :: struct {
	armed:       bool,
	prefab:      Prefab_Id,
	anchor:      [3]f32,
	height:      f32,
	yaw_degrees: f32,
	snap:        bool,
}

Placement_Geometry :: struct {
	center:       [3]f32,
	half_extents: [3]f32,
	rotation:     b3.Quat,
	bottom:       [3]f32,
	surface:      [3]f32,
}

placement_geometry :: proc(placement: Placement) -> Placement_Geometry {
	info := prefab(placement.prefab)
	rotation := object_rotation(placement.prefab, placement.yaw_degrees * math.PI / 180.0)
	bottom := placement.anchor + {0.0, placement.height, 0.0}
	if placement.snap {
		bottom.x = placement_snap(bottom.x)
		bottom.z = placement_snap(bottom.z)
	}
	extent := oriented_aabb_half_extents(info.half_extents, rotation)
	return {
		center = bottom + {0.0, extent.y, 0.0},
		half_extents = info.half_extents,
		rotation = rotation,
		bottom = bottom,
		surface = placement.anchor,
	}
}

@(private)
debug_placement_arm :: proc(dm: ^Debug_Mode, sim: ^Simulation, prefab_id: Prefab_Id) -> bool {
	if !simulation_is_valid(sim) {
		return false
	}
	debug_sun_cancel(dm)
	// The palette is the one place that holds the next placement's body and
	// light, so arming by prefab also selects it there.
	_ = palette_select(&dm.palette, int(prefab_id))
	dm.placement.armed = true
	dm.placement.prefab = prefab_id
	debug_placement_refresh(dm, sim)
	return true
}

@(private)
debug_placement_refresh :: proc(dm: ^Debug_Mode, sim: ^Simulation) {
	if !dm.placement.armed || !simulation_is_valid(sim) {
		return
	}
	dm.placement.anchor = placement_anchor(dm, sim)
}

@(private)
debug_placement_cancel :: proc(dm: ^Debug_Mode) {
	dm.placement.armed = false
}

@(private)
debug_placement_set_height :: proc(dm: ^Debug_Mode, height: f32) {
	dm.placement.height = max(height, 0.0)
}

@(private)
debug_placement_raise :: proc(dm: ^Debug_Mode, steps: int, large: bool) {
	step: f32 = large ? PLACEMENT_HEIGHT_STEP_LARGE : PLACEMENT_HEIGHT_STEP
	debug_placement_set_height(dm, dm.placement.height + f32(steps) * step)
}

@(private)
debug_placement_set_yaw :: proc(dm: ^Debug_Mode, degrees: f32) {
	dm.placement.yaw_degrees = degrees - 360.0 * math.floor(degrees / 360.0)
}

@(private)
debug_placement_turn :: proc(dm: ^Debug_Mode, steps: int, large: bool) {
	step: f32 = large ? PLACEMENT_YAW_STEP_LARGE : PLACEMENT_YAW_STEP
	debug_placement_set_yaw(dm, dm.placement.yaw_degrees + f32(steps) * step)
}

@(private)
debug_placement_set_snap :: proc(dm: ^Debug_Mode, snap: bool) {
	dm.placement.snap = snap
}

@(private)
debug_placement_toggle_snap :: proc(dm: ^Debug_Mode) {
	dm.placement.snap = !dm.placement.snap
}

debug_ghost_geometry :: proc(dm: ^Debug_Mode) -> (Placement_Geometry, bool) {
	if !dm.placement.armed {
		return {}, false
	}
	return placement_geometry(dm.placement), true
}

debug_ghost_box :: proc(dm: ^Debug_Mode) -> (geometry.Box, bool) {
	ghost, ok := debug_ghost_geometry(dm)
	if !ok {
		return {}, false
	}
	return {
		center = ghost.center,
		half_extents = ghost.half_extents,
		color = debug_ghost_color(dm),
		rotation = {ghost.rotation.x, ghost.rotation.y, ghost.rotation.z, ghost.rotation.w},
	}, true
}

debug_ghost_color :: proc(dm: ^Debug_Mode) -> [4]f32 {
	light := placement_light_for(dm, dm.placement.prefab)
	if light.active {
		return light_color4(light.color)
	}
	return GHOST_COLOR
}

@(private)
placement_anchor :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> [3]f32 {
	return debug_aim_point(dm, sim, PLACEMENT_FALLBACK_DISTANCE)
}

@(private)
placement_snap :: proc(value: f32) -> f32 {
	return math.round(value / PLACEMENT_SNAP_STEP) * PLACEMENT_SNAP_STEP
}
