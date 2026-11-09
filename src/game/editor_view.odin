#+vet explicit-allocators
package game

import "core:math"

import "src:geometry"

Editor_Palette_View :: struct {
	open:      bool,
	prefab:    Prefab_Id,
	body_mode: Body_Mode,
}

Editor_Placement_View :: struct {
	armed:       bool,
	prefab:      Prefab_Id,
	center:      [3]f32,
	height:      f32,
	yaw_degrees: f32,
	snap:        bool,
	light:       Light_Settings,
}

Editor_Selection_View :: struct {
	id:          Object_Id,
	prefab:      Prefab_Id,
	body_mode:   Body_Mode,
	box:         geometry.Box,
	yaw_degrees: f32,
	light:       Light_Settings,
}

Editor_History_View :: struct {
	depth: int,
	redo:  int,
}

Editor_Light_Budget :: struct {
	active: int,
	lamps:  int,
}

// The one resolved editor state for the selection, the placement, the history,
// and the light budget. The HUD and the harness format this value; they do not
// resolve those fields again.
Editor_View :: struct {
	active:    bool,
	tool:      Active_Tool,
	palette:   Editor_Palette_View,
	placement: Editor_Placement_View,
	selection: Maybe(Editor_Selection_View),
	history:   Editor_History_View,
	lights:    Editor_Light_Budget,
}

editor_view :: proc(dm: ^Debug_Mode, sim: ^Simulation) -> Editor_View {
	tool := active_tool(dm)
	view := Editor_View {
		active = dm.active,
		tool = tool,
		palette = {
			open = tool == .Palette,
			prefab = palette_selected(dm.palette),
			body_mode = dm.palette.body_mode,
		},
		placement = {
			armed = tool == .Placement,
			prefab = dm.placement.prefab,
			height = dm.placement.height,
			yaw_degrees = dm.placement.yaw_degrees,
			snap = dm.placement.snap,
			light = next_placement_light(dm),
		},
		history = {
			depth = debug_history_depth(dm),
			redo = debug_history_redo_depth(dm),
		},
		lights = {
			active = simulation_active_light_count(sim),
			lamps = simulation_lamp_count(sim),
		},
	}
	if ghost, ok := debug_ghost_geometry(dm); ok {
		view.placement.center = ghost.center
	}
	if id, ok := debug_selected_object_id(dm, sim); ok {
		if object, found := simulation_object_find(sim, id); found {
			view.selection = Editor_Selection_View {
				id = id,
				prefab = object.prefab,
				body_mode = object.body_mode,
				box = simulation_object_box(sim, id),
				yaw_degrees = simulation_object_yaw(sim, id) * 180.0 / math.PI,
				light = object.light,
			}
		}
	}
	return view
}
