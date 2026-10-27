#+vet explicit-allocators
#+vet !unused-procedures // main calls this API; test builds compile game as a dependency
package game

import "src:perf"
import "src:ui"

HUD_ROW_COUNT :: 6
// The debug inspector rows live in hud_debug.odin; the panel still reserves the
// widest debug mode so the perf rows fit after it.
HUD_PERF_ROW_COUNT :: 2
HUD_MAX_ROWS :: HUD_INSPECTOR_ROW_COUNT + HUD_PERF_ROW_COUNT

HUD_CAPTURE_HINT :: "Click to capture mouse"
HUD_HEADER_SEPARATOR :: " · "

HUD_Perf :: struct {
	visible: bool,
	stats:   perf.Stats,
}

HUD_State :: struct {
	view:         ui.Hud,
	rows:         [HUD_MAX_ROWS]ui.Row,
	storage:      Line_Buffer,
	capture_hint: string,
	captured:     bool,
	notice:       Notice_State,
	menu:         Menu_State,
	perf:         HUD_Perf,
}

hud_state_update :: proc(
	hud: ^HUD_State,
	sim: ^Simulation,
	debug: ^Debug_Mode,
	snapshot: Render_Snapshot,
	captured: bool,
	delta_seconds: f32,
) {
	hud.captured = captured
	hud.capture_hint = HUD_CAPTURE_HINT
	hud.view.notice = {text = hud_notice_text(hud)}
	menu_view(&hud.menu, &sim.settings, debug.active, delta_seconds)
	if debug.active {
		hud_debug_state_update(hud, sim, debug)
	} else {
		hud_player_state_update(hud, snapshot)
	}
	hud_perf_append(hud)
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
hud_perf_append :: proc(hud: ^HUD_State) {
	if !hud.perf.visible {
		return
	}
	index := len(hud.view.rows)
	if index >= HUD_MAX_ROWS {
		return
	}
	hud.rows[index] = {
		kind    = .Detail,
		label   = "Perf",
		value   = perf.format_summary(hud.storage.storage[index][:], hud.perf.stats),
		numeric = true,
	}
	index += 1
	if hud.perf.stats.gpu.available && index < HUD_MAX_ROWS {
		hud.rows[index] = {
			kind    = .Detail,
			label   = "Passes",
			value   = perf.format_passes(hud.storage.storage[index][:], hud.perf.stats),
			numeric = true,
		}
		index += 1
	}
	hud.view.rows = hud.rows[:index]
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
