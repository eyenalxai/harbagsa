#+vet explicit-allocators
package game

import "core:math"

import "src:ui"

INSPECTOR_LINE_SELECTION :: 0
INSPECTOR_LINE_YAW :: 1
INSPECTOR_LINE_PLACEMENT_HEIGHT :: 2
INSPECTOR_LINE_PLACEMENT_YAW :: 3
INSPECTOR_LINE_LAMP_INTENSITY :: 4
INSPECTOR_LINE_LAMP_RANGE :: 5
INSPECTOR_LINE_TYPE_WEIGHT :: 6

// The rail reads the same resolved editor view the HUD uses. Every changing
// number is formatted here; the shim draws the string and uses the numeric
// value only for a control position.
inspector_view :: proc(
	storage: ^Line_Buffer,
	debug: ^Debug_Mode,
	sim: ^Simulation,
	view: Editor_View,
) -> ui.Inspector {
	placement_prefab := "Choose in palette"
	if view.placement.armed {
		placement_prefab = prefab_name(view.placement.prefab)
	}
	inspector := ui.Inspector {
		open                  = editor_inspector_open(&debug.editor, debug.active),
		selection             = "None",
		yaw_text              = line_format(storage, INSPECTOR_LINE_YAW, "% 3.0f°", 0.0),
		placement_prefab      = placement_prefab,
		placement_height_text = line_format(
			storage,
			INSPECTOR_LINE_PLACEMENT_HEIGHT,
			"% 5.2f m",
			view.placement.height,
		),
		placement_yaw_text = line_format(
			storage,
			INSPECTOR_LINE_PLACEMENT_YAW,
			"% 3.0f°",
			inspector_yaw(view.placement.yaw_degrees),
		),
		placement_snap_text = view.placement.snap ? "0.25 m" : "off",
		type_weight         = sim.settings.type_weight,
		type_weight_text    = line_format(
			storage,
			INSPECTOR_LINE_TYPE_WEIGHT,
			"% 3.0f",
			sim.settings.type_weight,
		),
		physics_debug = debug.physics_debug,
	}
	for color in 0 ..< ui.INSPECTOR_LAMP_COLORS {
		inspector.lamp_colors[color] = light_color4(Light_Color(color))
	}
	if selection, has_selection := view.selection.?; has_selection {
		inspector.has_selection = true
		inspector.object_id = u32(selection.id)
		inspector.selection = line_format(
			storage,
			INSPECTOR_LINE_SELECTION,
			"%-11s  # %03d",
			prefab_name(selection.prefab),
			u32(selection.id),
		)
		inspector.body = int(selection.body_mode)
		inspector.yaw_degrees = selection.yaw_degrees
		inspector.yaw_text = line_format(
			storage,
			INSPECTOR_LINE_YAW,
			"% 3.0f°",
			selection.yaw_degrees,
		)
		if selection.light.active {
			inspector.has_lamp = true
			inspector.lamp_kind = int(selection.light.kind)
			inspector.lamp_color = int(selection.light.color)
			inspector.lamp_intensity = selection.light.intensity
			inspector.lamp_range = selection.light.range
			inspector.lamp_intensity_text = line_format(
				storage,
				INSPECTOR_LINE_LAMP_INTENSITY,
				"% 4.1f",
				selection.light.intensity,
			)
			inspector.lamp_range_text = line_format(
				storage,
				INSPECTOR_LINE_LAMP_RANGE,
				"% 2.0f m",
				selection.light.range,
			)
		}
	}
	return inspector
}

@(private)
inspector_yaw :: proc(degrees: f32) -> f32 {
	return degrees - 360.0 * math.floor(degrees / 360.0)
}
