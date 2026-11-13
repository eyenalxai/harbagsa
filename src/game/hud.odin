#+vet explicit-allocators
#+vet !unused-procedures // main calls this API; library checks compile game as a dependency
package game

import "src:ui"

HUD_ROW_COUNT :: 6
HUD_MAX_ROWS :: HUD_INSPECTOR_ROW_COUNT

HUD_CAPTURE_HINT :: "Click to capture mouse"
HUD_HEADER_SEPARATOR :: " · "

// The renderer owns the bake state; the HUD only needs the status and key.
Bake_View :: struct {
	status: string,
	key:    u64,
}

HUD_State :: struct {
	view:         ui.Hud,
	settings:     ui.Settings,
	rows:         [HUD_MAX_ROWS]ui.Row,
	storage:      Line_Buffer,
	capture_hint: string,
	captured:     bool,
	notice:       Notice_State,
	menu:         Menu_State,
}

hud_state_update :: proc(
	hud: ^HUD_State,
	sim: ^Simulation,
	debug: ^Debug_Mode,
	snapshot: Render_Snapshot,
	captured: bool,
	delta_seconds: f32,
	bake: Bake_View,
) {
	hud.captured = captured
	hud.capture_hint = HUD_CAPTURE_HINT
	hud.view.notice = {text = hud_notice_text(hud)}
	menu_view(&hud.menu, debug.active, delta_seconds)
	hud.settings = settings_view(&sim.settings)
	if debug.active {
		hud_debug_state_update(hud, sim, debug, bake)
	} else {
		hud_player_state_update(hud, snapshot)
	}
}


@(private)
hud_player_state_update :: proc(hud: ^HUD_State, snapshot: Render_Snapshot) {
	hud.rows[0] = {
		kind  = .Header,
		label = line_format(
			&hud.storage,
			0,
			"%s%s%s",
			"Spider",
			HUD_HEADER_SEPARATOR,
			gait_name(snapshot.gait),
		),
	}
	hud.rows[1] = {
		kind    = .Metric,
		label   = "Speed",
		value   = line_format(&hud.storage, 1, "% 4.1f m/s", horizontal_speed(snapshot.velocity)),
		numeric = true,
	}
	hud.rows[2] = {
		kind    = .Metric,
		label   = "Feet",
		value   = line_format(&hud.storage, 4, "%d planted", snapshot_planted_count(snapshot)),
		numeric = true,
	}
	hud.rows[3] = {kind = .Divider}
	hud.rows[4] = {kind = .Detail, label = "Grounded", value = grounded_name(snapshot.grounded)}
	hud.rows[5] = {
		kind    = .Detail,
		label   = "Position",
		value   = hud_arena_position(&hud.storage, 2, snapshot.position),
		numeric = true,
	}
	hud.view.rows = hud.rows[:HUD_ROW_COUNT]
}

@(private)
hud_arena_position :: proc(buffer: ^Line_Buffer, slot: int, position: [3]f32) -> string {
	return line_format(
		buffer,
		slot,
		"X % 5.1f  Y % 5.1f  Z % 5.1f",
		snap_near_zero(position.x),
		snap_near_zero(position.y),
		snap_near_zero(position.z),
	)
}

@(private)
grounded_name :: proc(grounded: bool) -> string {
	return grounded ? "yes" : "no"
}

@(private)
snap_near_zero :: proc(value: f32) -> f32 {
	if value > -0.05 && value < 0.05 {
		return 0
	}
	return value
}
