#+vet explicit-allocators
package harness

import "core:mem"
import "core:strings"

import "src:game"
import "src:ui"

Row_State :: struct {
	kind:    string  `json:"kind"`,
	label:   string  `json:"label"`,
	value:   string  `json:"value"`,
	blocked: bool    `json:"blocked"`,
	ratio:   f32     `json:"ratio"`,
	ticks:   int     `json:"ticks"`,
}

Rows_State :: struct {
	hud:  []Row_State `json:"hud"`,
	menu: []Row_State `json:"menu"`,
}

// The rows are the layer the renderer draws, so a scenario can assert a label,
// a blocked row, or a slider ratio without decoding a PNG.
rows_state_build :: proc(hud: ^game.HUD_State, allocator: mem.Allocator) -> Rows_State {
	return {
		hud = rows_build(hud.view.rows, allocator),
		menu = rows_build(hud.menu.view.rows, allocator),
	}
}

rows_state_destroy :: proc(state: ^Rows_State, allocator: mem.Allocator) {
	rows_destroy(state.hud, allocator)
	rows_destroy(state.menu, allocator)
	state^ = {}
}

session_refresh_hud :: proc(session: ^Session) {
	game.hud_state_update(
		&session.hud,
		&session.sim,
		&session.debug,
		game.simulation_snapshot(&session.sim),
		false,
	)
}

@(private)
rows_build :: proc(rows: []ui.Row, allocator: mem.Allocator) -> []Row_State {
	result := make([]Row_State, len(rows), allocator)
	for row, index in rows {
		result[index] = {
			kind    = row_kind_name(row.kind),
			label   = strings.clone(row.label, allocator),
			value   = strings.clone(row.value, allocator),
			blocked = row.blocked,
			ratio   = row.ratio,
			ticks   = row.ticks,
		}
	}
	return result
}

@(private)
rows_destroy :: proc(rows: []Row_State, allocator: mem.Allocator) {
	for &row in rows {
		// `kind` names a constant, so only the label and value own memory.
		if row.label != "" {
			delete(row.label, allocator)
		}
		if row.value != "" {
			delete(row.value, allocator)
		}
	}
	if rows != nil {
		delete(rows, allocator)
	}
}

@(private)
row_kind_name :: proc(kind: ui.Row_Kind) -> string {
	switch kind {
	case .Setting:
		return "setting"
	case .Action:
		return "action"
	case .Metric:
		return "metric"
	case .Detail:
		return "detail"
	case .Slider:
		return "slider"
	case .Divider:
		return "divider"
	case .Header:
		return "header"
	}
	return "unknown"
}
