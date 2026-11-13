#+vet explicit-allocators
package game

import "src:ui"

// The rail reads the same resolved editor view the HUD uses. The selection is
// authoritative; a deleted object clears the section on the next snapshot.
inspector_view :: proc(debug: ^Debug_Mode, sim: ^Simulation, view: Editor_View) -> ui.Inspector {
	inspector := ui.Inspector {
		open                  = view.active && debug.editor.inspector_open,
		placement_prefab      = prefab_name(view.placement.prefab),
		placement_height      = view.placement.height,
		placement_yaw_degrees = view.placement.yaw_degrees,
		placement_snap        = view.placement.snap,
		type_weight           = sim.settings.type_weight,
		physics_debug         = debug.physics_debug,
	}
	for color in 0 ..< ui.INSPECTOR_LAMP_COLORS {
		inspector.lamp_colors[color] = light_color4(Light_Color(color))
	}
	if selection, has_selection := view.selection.?; has_selection {
		inspector.has_selection = true
		inspector.object_id = u32(selection.id)
		inspector.prefab = prefab_name(selection.prefab)
		inspector.body = int(selection.body_mode)
		inspector.yaw_degrees = selection.yaw_degrees
		if selection.light.active {
			inspector.has_lamp = true
			inspector.lamp_kind = int(selection.light.kind)
			inspector.lamp_color = int(selection.light.color)
			inspector.lamp_intensity = selection.light.intensity
			inspector.lamp_range = selection.light.range
		}
	}
	return inspector
}
