#+vet explicit-allocators
#+vet !unused-procedures // main calls this API; test builds compile game as a dependency
package game

import "core:math"

import "src:perf"
import "src:ui"

HUD_ROW_COUNT :: 6
HUD_PERF_ROW_COUNT :: 2
HUD_MAX_ROWS :: HUD_ROW_COUNT + HUD_PERF_ROW_COUNT

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
	menu_view(&hud.menu, sim.settings, debug.active, delta_seconds)
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
			stance_name(snapshot.stance),
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
	hud.rows[2] = {kind = .Metric, label = "State", value = movement_state_name(snapshot.movement_state)}
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
	index := HUD_ROW_COUNT
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
hud_debug_state_update :: proc(hud: ^HUD_State, sim: ^Simulation, debug: ^Debug_Mode) {
	selected := "None"
	if id, ok := debug_selected_object_id(debug, sim); ok {
		if object, found := simulation_object_find(sim, id); found {
			selected = prefab_name(object.prefab)
		}
	}
	if debug.selection == .Sun {
		selected = "Sun"
	}

	azimuth, elevation := debug_mode_sun_angles(debug)
	camera := debug.camera.position

	hud.rows[0] = {kind = .Header, label = "Debug mode"}
	hud.rows[1] = {kind = .Metric, label = "Selection", value = selected}
	hud.rows[2] = {
		kind    = .Metric,
		label   = "Objects",
		value   = line_format(&hud.storage, 0, "% 2d", simulation_object_count(sim)),
		numeric = true,
	}
	hud.rows[3] = {kind = .Divider}
	hud.rows[4] = {
		kind    = .Detail,
		label   = "Position",
		value   = hud_camera_position(&hud.storage, 1, camera),
		numeric = true,
	}
	hud.rows[5] = {
		kind    = .Detail,
		label   = "Sun",
		value   = line_format(
			&hud.storage,
			2,
			"az % 4.0f  el % 4.0f",
			azimuth * 180.0 / math.PI,
			elevation * 180.0 / math.PI,
		),
		numeric = true,
	}
	hud.view.rows = hud.rows[:HUD_ROW_COUNT]
}

// Every number that changes while the player moves is formatted into a fixed
// field, so the row width never changes and the panel never resizes. The arena
// spans 40 m; the debug camera is unclamped and gets two more columns.
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
hud_camera_position :: proc(buffer: ^Line_Buffer, slot: int, position: [3]f32) -> string {
	return line_format(
		buffer,
		slot,
		"X % 7.1f  Y % 7.1f  Z % 7.1f",
		position.x,
		position.y,
		position.z,
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
