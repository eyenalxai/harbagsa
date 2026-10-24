#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:math"
import "core:testing"

import "src:display"
import game "src:game"
import "src:ui"

@(test)
slider_hit_uses_the_full_track_and_the_knob_travel :: proc(t: ^testing.T) {
	rect := ui.Slider_Rect{x = 10, y = 20, width = 100, height = 12, knob = 10}

	left, left_inside := ui.slider_hit(rect, {10, 26})
	testing.expect(t, left_inside, "the left track edge is outside")
	testing.expect_value(t, left, f32(0))

	left_knob, left_knob_inside := ui.slider_hit(rect, {15, 26})
	testing.expect(t, left_knob_inside, "the left knob edge is outside")
	testing.expect_value(t, left_knob, f32(0))

	middle, middle_inside := ui.slider_hit(rect, {60, 26})
	testing.expect(t, middle_inside, "the midpoint is outside")
	testing.expect(t, math.abs(middle - 0.5) < 0.0001, "the midpoint ratio is wrong")

	right_knob, right_knob_inside := ui.slider_hit(rect, {105, 26})
	testing.expect(t, right_knob_inside, "the right knob edge is outside")
	testing.expect_value(t, right_knob, f32(1))

	right, right_inside := ui.slider_hit(rect, {110, 26})
	testing.expect(t, right_inside, "the right track edge is outside")
	testing.expect_value(t, right, f32(1))
}

@(test)
slider_hit_rejects_points_outside_the_track :: proc(t: ^testing.T) {
	rect := ui.Slider_Rect{x = 10, y = 20, width = 100, height = 12, knob = 10}

	_, left := ui.slider_hit(rect, {9, 26})
	testing.expect(t, !left, "a point left of the track is inside")

	_, right := ui.slider_hit(rect, {111, 26})
	testing.expect(t, !right, "a point right of the track is inside")

	_, above := ui.slider_hit(rect, {60, 19})
	testing.expect(t, !above, "a point above the track is inside")

	_, below := ui.slider_hit(rect, {60, 33})
	testing.expect(t, !below, "a point below the track is inside")
}

@(test)
slider_hit_handles_a_zero_width_track :: proc(t: ^testing.T) {
	rect := ui.Slider_Rect{x = 10, y = 20, width = 0, height = 12, knob = 10}
	ratio, inside := ui.slider_hit(rect, {10, 26})
	testing.expect(t, !inside, "a zero width track has an inside point")
	testing.expect_value(t, ratio, f32(0))
}

@(test)
slider_hit_clamps_the_ratio_outside_the_travel :: proc(t: ^testing.T) {
	rect := ui.Slider_Rect{x = 10, y = 20, width = 100, height = 12, knob = 10}

	left, _ := ui.slider_hit(rect, {0, 26})
	testing.expect_value(t, left, f32(0))

	right, _ := ui.slider_hit(rect, {200, 26})
	testing.expect_value(t, right, f32(1))
}

@(private)
slider_test_rect :: proc() -> ui.Slider_Rect {
	return {x = 20, y = 40, width = 200, height = 12, knob = 8}
}

// The point at a ratio sits on the knob centre, which is what the draw uses.
@(private)
slider_test_point :: proc(rect: ui.Slider_Rect, ratio: f32) -> [2]f32 {
	travel := rect.width - rect.knob
	return {rect.x + rect.knob * 0.5 + ratio * travel, rect.y + rect.height * 0.5}
}

@(test)
menu_slider_press_at_the_left_knob_sets_the_minimum :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	menu: game.Menu_State
	game.menu_open(&menu)
	rect := slider_test_rect()

	game.menu_slider_input(
		&menu,
		&sim.settings,
		rect,
		{rect.x, rect.y + rect.height * 0.5},
		true,
		true,
	)

	testing.expect(t, menu.dragging_weight, "the left knob edge did not start a drag")
	testing.expect_value(t, menu.selected, game.Menu_Item.Type_Weight)
	testing.expect_value(t, sim.settings.type_weight, f32(ui.TYPE_WEIGHT_MIN))
}

@(test)
menu_slider_press_at_the_right_knob_sets_the_maximum :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	menu: game.Menu_State
	game.menu_open(&menu)
	rect := slider_test_rect()

	game.menu_slider_input(
		&menu,
		&sim.settings,
		rect,
		{rect.x + rect.width, rect.y + rect.height * 0.5},
		true,
		true,
	)

	testing.expect(t, menu.dragging_weight, "the right knob edge did not start a drag")
	testing.expect_value(t, sim.settings.type_weight, f32(ui.TYPE_WEIGHT_MAX))
}

@(test)
menu_slider_drag_updates_the_weight :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	menu: game.Menu_State
	game.menu_open(&menu)
	rect := slider_test_rect()

	game.menu_slider_input(&menu, &sim.settings, rect, slider_test_point(rect, 0.5), true, true)
	testing.expect_value(t, sim.settings.type_weight, f32(500))

	game.menu_slider_input(&menu, &sim.settings, rect, slider_test_point(rect, 0.75), false, true)
	testing.expect_value(t, sim.settings.type_weight, f32(700))
	testing.expect(t, menu.dragging_weight, "the drag ended while the pointer was down")
}

@(test)
menu_slider_release_ends_the_drag :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	menu: game.Menu_State
	game.menu_open(&menu)
	rect := slider_test_rect()

	game.menu_slider_input(&menu, &sim.settings, rect, slider_test_point(rect, 0.5), true, true)
	game.menu_slider_input(&menu, &sim.settings, rect, slider_test_point(rect, 1), false, false)

	testing.expect(t, !menu.dragging_weight, "the release left the drag on")
	testing.expect_value(t, sim.settings.type_weight, f32(500))

	game.menu_slider_input(&menu, &sim.settings, rect, slider_test_point(rect, 1), false, true)
	testing.expect_value(t, sim.settings.type_weight, f32(500))
}

@(test)
menu_slider_ignores_a_press_off_the_track_or_closed_menu :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	menu: game.Menu_State
	rect := slider_test_rect()

	game.menu_slider_input(&menu, &sim.settings, rect, slider_test_point(rect, 0), true, true)
	testing.expect(t, !menu.dragging_weight, "a closed menu started a drag")

	game.menu_open(&menu)
	game.menu_slider_input(&menu, &sim.settings, rect, {rect.x, rect.y - 1}, true, true)
	testing.expect(t, !menu.dragging_weight, "a press above the track started a drag")
	testing.expect_value(t, sim.settings.type_weight, f32(400))
}

@(test)
menu_slider_press_on_the_opening_frame_starts_the_drag :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	menu: game.Menu_State
	menu.displays = display.fallback_list()
	game.menu_open(&menu)
	// The opening frame has no published rect, so the caller refreshes the view
	// and measures the Type weight row before it reads the pointer.
	game.menu_view(&menu, sim.settings, false)

	row_index := game.MENU_ITEM_ROWS[game.Menu_Item.Type_Weight]
	row := menu.view.rows[row_index]
	testing.expect_value(t, row.kind, ui.Row_Kind.Slider)

	rect := slider_test_rect()
	knob := slider_test_point(rect, row.ratio)
	game.menu_slider_input(&menu, &sim.settings, rect, knob, true, true)

	testing.expect(t, menu.dragging_weight, "the opening-frame press did not start a drag")
	testing.expect_value(t, menu.selected, game.Menu_Item.Type_Weight)
	testing.expect_value(t, sim.settings.type_weight, f32(400))
}
