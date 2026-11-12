#+vet explicit-allocators
package game

HUD_INSPECTOR_ROW_COUNT :: 12
HUD_PLACEMENT_ROW_COUNT :: 9

HUD_SNAP_OFF :: "off"
HUD_SNAP_GRID :: "0.25 m"

// The selection, the count, the body, the size, the position, the yaw, and the
// snap state. Every changing value uses a fixed field through `numeric`, so the
// panel width does not move when the selection changes.
@(private)
hud_debug_state_update :: proc(
	hud: ^HUD_State,
	sim: ^Simulation,
	debug: ^Debug_Mode,
	bake: Bake_View,
) {
	view := editor_view(&debug.editor, sim, debug.active, debug.camera)
	if view.tool == .Placement {
		hud_placement_state_update(hud, sim, view, bake)
		return
	}
	hud_inspector_state_update(hud, sim, view, debug.camera, bake)
}

@(private)
hud_inspector_state_update :: proc(
	hud: ^HUD_State,
	sim: ^Simulation,
	view: Editor_View,
	camera: Debug_Camera,
	bake: Bake_View,
) {
	name := "None"
	body := "none"
	half_extents: [3]f32
	position: [3]f32
	yaw: f32
	light: Light_Settings
	selected_id := INVALID_OBJECT_ID
	if selection, has_selection := view.selection.?; has_selection {
		name = prefab_name(selection.prefab)
		body = body_mode_name(selection.body_mode)
		half_extents = selection.box.half_extents
		position = selection.box.center
		yaw = selection.yaw_degrees
		light = selection.light
		selected_id = selection.id
	}

	hud.rows[0] = {kind = .Header, label = "Debug mode"}
	hud.rows[1] = {
		kind    = .Metric,
		label   = "Selection",
		value   = line_format(&hud.storage, 0, "%-11s  # %03d", name, u32(selected_id)),
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
	if view.placement.snap {
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
			camera.position.x,
			camera.position.y,
			camera.position.z,
		),
		numeric = true,
	}
	hud.rows[9] = {
		kind    = .Detail,
		label   = "Light",
		value   = hud_light_line(hud, 9, light),
		numeric = true,
	}
	hud.rows[10] = {
		kind    = .Detail,
		label   = "Lights",
		value   = hud_light_budget(hud, 10, view.lights),
		numeric = true,
	}
	hud.rows[11] = {
		kind    = .Detail,
		label   = "Bake",
		value   = hud_bake_line(hud, 11, bake),
		numeric = true,
	}
	hud.view.rows = hud.rows[:HUD_INSPECTOR_ROW_COUNT]
}

@(private)
hud_placement_state_update :: proc(
	hud: ^HUD_State,
	sim: ^Simulation,
	view: Editor_View,
	bake: Bake_View,
) {
	placement := view.placement
	hud.rows[0] = {kind = .Header, label = "Debug mode"}
	hud.rows[1] = {
		kind  = .Metric,
		label = "Prefab",
		value = prefab_name(placement.prefab),
	}
	hud.rows[2] = {
		kind  = .Metric,
		label = "Body",
		value = body_mode_name(placement.body_mode),
	}
	hud.rows[3] = {
		kind    = .Metric,
		label   = "Height",
		value   = line_format(&hud.storage, 3, "% 6.2f m", placement.height),
		numeric = true,
	}
	hud.rows[4] = {
		kind    = .Metric,
		label   = "Yaw",
		value   = line_format(&hud.storage, 4, "% 6.1f deg", placement.yaw_degrees),
		numeric = true,
	}
	snap := HUD_SNAP_OFF
	if placement.snap {
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
	hud.rows[7] = {
		kind    = .Metric,
		label   = "Light",
		value   = hud_light_line(hud, 7, placement.light),
		numeric = true,
	}
	hud.rows[8] = {
		kind    = .Detail,
		label   = "Bake",
		value   = hud_bake_line(hud, 8, bake),
		numeric = true,
	}
	hud.view.rows = hud.rows[:HUD_PLACEMENT_ROW_COUNT]
}

@(private)
hud_light_line :: proc(hud: ^HUD_State, slot: int, light: Light_Settings) -> string {
	kind := "none"
	name := "none"
	if light.active {
		kind = lamp_kind_name(light.kind)
		name = light_color_name(light.color)
	}
	return line_format(
		&hud.storage,
		slot,
		"%-7s %-5s % 4.1f % 2.0f m",
		kind,
		name,
		light.intensity,
		light.range,
	)
}

@(private)
hud_bake_line :: proc(hud: ^HUD_State, slot: int, bake: Bake_View) -> string {
	if bake.status != "current" && bake.status != "stale" {
		return line_format(&hud.storage, slot, "%-7s", bake.status)
	}
	return line_format(&hud.storage, slot, "%-7s %016x", bake.status, bake.key)
}

@(private)
hud_light_budget :: proc(hud: ^HUD_State, slot: int, budget: Light_Budget) -> string {
	return line_format(
		&hud.storage,
		slot,
		"% 2d active / % 2d lamps",
		budget.active,
		budget.lamps,
	)
}
