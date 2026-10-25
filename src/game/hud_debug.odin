#+vet explicit-allocators
package game

import "core:math"

HUD_INSPECTOR_ROW_COUNT :: 12
HUD_INSPECTOR_SUN_ROW_COUNT :: 13
HUD_PLACEMENT_ROW_COUNT :: 8

HUD_SNAP_OFF :: "off"
HUD_SNAP_GRID :: "0.25 m"

// The selection, the count, the body, the size, the position, the yaw, and the
// snap state. Every changing value uses a fixed field and the mono face through
// `numeric`, so the panel width does not move when the selection changes.
@(private)
hud_debug_state_update :: proc(hud: ^HUD_State, sim: ^Simulation, debug: ^Debug_Mode) {
	if debug.placement.armed {
		hud_placement_state_update(hud, sim, debug)
		return
	}

	id, has_selection := debug_selected_object_id(debug, sim)
	name := "None"
	body := "none"
	half_extents: [3]f32
	position: [3]f32
	yaw: f32
	light: Light_Settings
	if has_selection {
		if object, found := simulation_object_find(sim, id); found {
			name = prefab_name(object.prefab)
			body = body_mode_name(object.body_mode)
			box := simulation_object_box(sim, id)
			half_extents = box.half_extents
			position = box.center
			yaw = simulation_object_yaw(sim, id) * 180.0 / math.PI
			light = object.light
		}
	}

	azimuth, elevation := debug_mode_sun_angles(debug)
	camera := debug.camera.position

	hud.rows[0] = {kind = .Header, label = "Debug mode"}
	hud.rows[1] = {
		kind    = .Metric,
		label   = "Selection",
		value   = line_format(&hud.storage, 0, "%-11s  # %03d", name, u32(id)),
		numeric = true,
	}
	hud.rows[2] = {
		kind    = .Metric,
		label   = "Objects",
		value   = line_format(
			&hud.storage,
			1,
			"% 3d",
			simulation_object_count(sim),
		),
		numeric = true,
	}
	hud.rows[3] = {
		kind    = .Metric,
		label   = "Body",
		value   = line_format(&hud.storage, 2, "%-7s", body),
		numeric = true,
	}
	hud.rows[4] = {
		kind    = .Detail,
		label   = "Size",
		value   = line_format(
			&hud.storage,
			3,
			"% 4.1f × % 4.1f × % 4.1f m",
			half_extents.x * 2.0,
			half_extents.y * 2.0,
			half_extents.z * 2.0,
		),
		numeric = true,
	}
	hud.rows[5] = {
		kind    = .Detail,
		label   = "Position",
		value   = line_format(
			&hud.storage,
			4,
			"X % 7.1f  Y % 7.1f  Z % 7.1f",
			position.x,
			position.y,
			position.z,
		),
		numeric = true,
	}
	hud.rows[6] = {
		kind    = .Detail,
		label   = "Yaw",
		value   = line_format(&hud.storage, 5, "% 7.1f deg", yaw),
		numeric = true,
	}
	snap := HUD_SNAP_OFF
	if debug.placement.snap {
		snap = HUD_SNAP_GRID
	}
	hud.rows[7] = {
		kind    = .Detail,
		label   = "Snap",
		value   = line_format(&hud.storage, 6, "%-6s", snap),
		numeric = true,
	}
	hud.rows[8] = {
		kind    = .Detail,
		label   = "Camera",
		value   = line_format(
			&hud.storage,
			7,
			"X % 7.1f  Y % 7.1f  Z % 7.1f",
			camera.x,
			camera.y,
			camera.z,
		),
		numeric = true,
	}
	hud.rows[9] = {
		kind    = .Detail,
		label   = "Sun",
		value   = line_format(
			&hud.storage,
			8,
			"az % 4.0f  el % 4.0f",
			azimuth * 180.0 / math.PI,
			elevation * 180.0 / math.PI,
		),
		numeric = true,
	}
	hud.rows[10] = {
		kind    = .Detail,
		label   = "Light",
		value   = hud_light_line(hud, 10, light),
		numeric = true,
	}
	hud.rows[11] = {
		kind    = .Detail,
		label   = "Lights",
		value   = hud_light_budget(hud, 11, sim),
		numeric = true,
	}
	row_count := HUD_INSPECTOR_ROW_COUNT
	if debug.sun.active {
		hud.rows[HUD_INSPECTOR_ROW_COUNT] = {
			kind  = .Metric,
			label = "Sun mode",
			value = "click place · Esc cancel",
		}
		row_count = HUD_INSPECTOR_SUN_ROW_COUNT
	}
	hud.view.rows = hud.rows[:row_count]
}

@(private)
hud_placement_state_update :: proc(hud: ^HUD_State, sim: ^Simulation, debug: ^Debug_Mode) {
	hud.rows[0] = {kind = .Header, label = "Debug mode"}
	hud.rows[1] = {
		kind  = .Metric,
		label = "Prefab",
		value = prefab_name(debug.placement.prefab),
	}
	hud.rows[2] = {
		kind  = .Metric,
		label = "Body",
		value = body_mode_name(debug.palette.body_mode),
	}
	hud.rows[3] = {
		kind    = .Metric,
		label   = "Height",
		value   = line_format(&hud.storage, 3, "% 6.2f m", debug.placement.height),
		numeric = true,
	}
	hud.rows[4] = {
		kind    = .Metric,
		label   = "Yaw",
		value   = line_format(&hud.storage, 4, "% 6.1f deg", debug.placement.yaw_degrees),
		numeric = true,
	}
	snap := HUD_SNAP_OFF
	if debug.placement.snap {
		snap = HUD_SNAP_GRID
	}
	hud.rows[5] = {kind = .Metric, label = "Snap", value = snap}
	hud.rows[6] = {
		kind    = .Metric,
		label   = "Objects",
		value   = line_format(
			&hud.storage,
			6,
			"% 3d",
			simulation_object_count(sim),
		),
		numeric = true,
	}
	light := next_placement_light(debug)
	hud.rows[7] = {
		kind    = .Metric,
		label   = "Light",
		value   = hud_light_line(hud, 7, light),
		numeric = true,
	}
	hud.view.rows = hud.rows[:HUD_PLACEMENT_ROW_COUNT]
}

@(private)
hud_light_line :: proc(hud: ^HUD_State, slot: int, light: Light_Settings) -> string {
	name := "none"
	if light.active {
		name = light_color_name(light.color)
	}
	return line_format(
		&hud.storage,
		slot,
		"%-5s % 4.1f % 2.0f m",
		name,
		light.intensity,
		light.range,
	)
}

@(private)
hud_light_budget :: proc(hud: ^HUD_State, slot: int, sim: ^Simulation) -> string {
	return line_format(
		&hud.storage,
		slot,
		"% 2d active / % 2d lamps",
		simulation_active_light_count(sim),
		simulation_lamp_count(sim),
	)
}
