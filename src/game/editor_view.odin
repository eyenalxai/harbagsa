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
	body_mode:   Body_Mode,
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

// The one resolved editor state for the tool, the selection, the placement, the
// history, and the light budget. The HUD and the harness format this value; they
// do not resolve those fields again.
Editor_View :: struct {
	active:    bool,
	tool:      Editor_Tool,
	palette:   Editor_Palette_View,
	placement: Editor_Placement_View,
	selection: Maybe(Editor_Selection_View),
	history:   Editor_History_View,
	lights:    Editor_Light_Budget,
}

editor_view :: proc(
	editor: ^Editor,
	sim: ^Simulation,
	active: bool,
	camera: Debug_Camera,
) -> Editor_View {
	default_prefab := prefab(.Crate)
	view := Editor_View {
		active = active,
		tool = editor_tool_kind(editor.tool),
		palette = {
			prefab = .Crate,
			body_mode = default_prefab.body_mode,
		},
		placement = {
			prefab = .Crate,
			body_mode = default_prefab.body_mode,
			light = prefab_light(.Crate),
		},
		history = {
			depth = editor_history_depth(editor),
			redo = editor_history_redo_depth(editor),
		},
		lights = {
			active = simulation_active_light_count(sim),
			lamps = simulation_lamp_count(sim),
		},
	}

	switch tool in editor.tool {
	case Palette:
		selected := palette_selected(tool)
		view.palette = {
			open = true,
			prefab = selected,
			body_mode = tool.body_mode,
		}
		view.placement.prefab = selected
		view.placement.light = palette_light(tool)
	case Placement:
		view.palette = {
			prefab = tool.prefab,
			body_mode = tool.body_mode,
		}
		view.placement = {
			armed = true,
			prefab = tool.prefab,
			height = tool.height,
			yaw_degrees = tool.yaw_degrees,
			snap = tool.snap,
			body_mode = tool.body_mode,
			light = tool.light,
		}
		if ghost, ok := editor_placement_geometry(editor, sim, camera); ok {
			view.placement.center = ghost.center
		}
	case Tool_None:
	}

	if id, ok := editor_selected_object_id(editor, sim); ok {
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
