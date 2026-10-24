#+vet explicit-allocators
package game

import "core:math"

import "src:ui"

menu_set_type_weight :: proc(menu: ^Menu_State, settings: ^Settings, weight: f32) -> bool {
	if !menu.open {
		return false
	}
	next := clamp(math.round(weight), ui.TYPE_WEIGHT_MIN, ui.TYPE_WEIGHT_MAX)
	if next != settings.type_weight {
		settings.type_weight = next
		menu_clear_status(menu)
	}
	return true
}

menu_set_type_weight_ratio :: proc(menu: ^Menu_State, settings: ^Settings, ratio: f32) -> bool {
	span := ui.TYPE_WEIGHT_MAX - ui.TYPE_WEIGHT_MIN
	return menu_set_type_weight(menu, settings, ui.TYPE_WEIGHT_MIN + clamp(ratio, 0, 1) * span)
}
