#+vet explicit-allocators
package game

import "src:ui"

// The drag state machine belongs to the game, not to the window loop, so the
// caller can drive the pointer without a renderer.
menu_weight_input :: proc(
	menu: ^Menu_State,
	settings: ^Settings,
	rect: ui.Slider_Rect,
	pointer: [2]f32,
	pressed, down: bool,
) {
	if !menu.open || rect.width <= 0 {
		return
	}
	ratio, inside := ui.slider_hit(rect, pointer)
	if pressed && inside {
		menu_select(menu, int(Menu_Item.Type_Weight))
		menu.dragging_weight = true
	}
	if !menu.dragging_weight {
		return
	}
	if !down {
		menu.dragging_weight = false
		return
	}
	_ = menu_set_type_weight_ratio(menu, settings, ratio)
}
