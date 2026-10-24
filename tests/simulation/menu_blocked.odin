#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import "src:display"
import game "src:game"

@(test)
display_press_is_blocked_with_one_display :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	menu: game.Menu_State
	menu.displays = one_display({1920, 1080}, true)
	game.menu_open(&menu)
	game.menu_select(&menu, 1)

	result := game.menu_change_setting(&menu, &sim.settings, 1)
	testing.expect_value(t, result, game.Change_Result.Blocked)
	testing.expect_value(t, menu.status, game.MENU_STATUS_ONE_DISPLAY)
	testing.expect_value(t, sim.settings.window.display, 0)

	game.menu_view(&menu, sim.settings, false)
	testing.expect(t, menu.view.rows[1].blocked, "the Display row is not blocked")
	testing.expect_value(t, menu.status, "")
}

@(test)
a_successful_change_clears_a_blocked_note :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	menu: game.Menu_State
	menu.displays = one_display({1920, 1080}, true)
	game.menu_open(&menu)
	game.menu_select(&menu, 1)

	result := game.menu_change_setting(&menu, &sim.settings, -1)
	testing.expect_value(t, result, game.Change_Result.Blocked)
	testing.expect_value(t, menu.status, game.MENU_STATUS_ONE_DISPLAY)

	game.menu_select(&menu, 3)
	result = game.menu_change_setting(&menu, &sim.settings, 1)
	testing.expect_value(t, result, game.Change_Result.Changed)
	testing.expect_value(t, menu.status, "")

	game.menu_view(&menu, sim.settings, false)
	testing.expect_value(t, menu.view.note, game.MENU_NOTE)
}

@(test)
resolution_press_is_blocked_without_modes :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	menu: game.Menu_State
	menu.displays = one_display({}, false)
	game.menu_open(&menu)
	game.menu_select(&menu, 2)

	result := game.menu_change_setting(&menu, &sim.settings, 1)
	testing.expect_value(t, result, game.Change_Result.Blocked)
	testing.expect_value(t, menu.status, game.MENU_STATUS_NO_MODES)
	testing.expect_value(t, sim.settings.window.resolution, display.Mode{1280, 720})

	game.menu_view(&menu, sim.settings, false)
	testing.expect(t, menu.view.rows[2].blocked, "the Resolution row is not blocked")
}

@(test)
windowed_resolution_press_is_blocked_with_one_mode :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	sim.settings.window.mode = .Windowed
	sim.settings.window.resolution = {1920, 1080}
	menu: game.Menu_State
	menu.displays = one_display({1920, 1080}, true)
	game.menu_open(&menu)
	game.menu_select(&menu, 2)

	result := game.menu_change_setting(&menu, &sim.settings, 1)
	testing.expect_value(t, result, game.Change_Result.Blocked)
	testing.expect_value(t, menu.status, game.MENU_STATUS_ONE_MODE)
	testing.expect_value(t, sim.settings.window.resolution, display.Mode{1920, 1080})

	game.menu_view(&menu, sim.settings, false)
	testing.expect(t, menu.view.rows[2].blocked, "the Resolution row is not blocked")

	sim.settings.window.mode = .Borderless
	menu.status = ""
	game.menu_view(&menu, sim.settings, false)
	testing.expect(t, !menu.view.rows[2].blocked, "a borderless resolution is blocked")

	result = game.menu_change_setting(&menu, &sim.settings, 1)
	testing.expect_value(t, result, game.Change_Result.Changed)
	testing.expect_value(t, sim.settings.window.mode, display.Window_Mode.Windowed)
}

@(test)
weight_press_is_blocked_at_the_axis_limits :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	menu: game.Menu_State
	game.menu_open(&menu)
	game.menu_select(&menu, 3)

	sim.settings.type_weight = 900
	result := game.menu_change_setting(&menu, &sim.settings, 1)
	testing.expect_value(t, result, game.Change_Result.Blocked)
	testing.expect_value(t, menu.status, game.MENU_STATUS_MAX_WEIGHT)
	testing.expect_value(t, sim.settings.type_weight, 900)
	game.menu_view(&menu, sim.settings, false)
	testing.expect(t, !menu.view.rows[3].blocked, "the weight row is blocked at the maximum")

	sim.settings.type_weight = 100
	menu.status = ""
	result = game.menu_change_setting(&menu, &sim.settings, -1)
	testing.expect_value(t, result, game.Change_Result.Blocked)
	testing.expect_value(t, menu.status, game.MENU_STATUS_MIN_WEIGHT)
	testing.expect_value(t, sim.settings.type_weight, 100)
	game.menu_view(&menu, sim.settings, false)
	testing.expect(t, !menu.view.rows[3].blocked, "the weight row is blocked at the minimum")

	result = game.menu_change_setting(&menu, &sim.settings, 1)
	testing.expect_value(t, result, game.Change_Result.Changed)
	testing.expect_value(t, sim.settings.type_weight, 110)
}

@(test)
blocked_status_lasts_one_rendered_frame :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	menu: game.Menu_State
	game.menu_open(&menu)
	game.menu_select(&menu, 3)
	sim.settings.type_weight = 900

	_ = game.menu_change_setting(&menu, &sim.settings, 1)
	game.menu_view(&menu, sim.settings, false)
	testing.expect_value(t, menu.view.note, game.MENU_STATUS_MAX_WEIGHT)
	testing.expect_value(t, menu.status, "")

	game.menu_view(&menu, sim.settings, false)
	testing.expect_value(t, menu.view.note, game.MENU_NOTE)
}

@(test)
enter_on_a_blocked_row_keeps_the_menu_open :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	menu: game.Menu_State
	menu.displays = one_display({1920, 1080}, true)
	game.menu_open(&menu)
	game.menu_select(&menu, 1)

	closed := game.menu_activate(&menu, &sim.settings)
	testing.expect(t, !closed, "a blocked row closed the menu")
	testing.expect(t, menu.open, "a blocked row closed the menu")
	testing.expect_value(t, menu.status, game.MENU_STATUS_ONE_DISPLAY)
}

@(private)
one_display :: proc(mode: display.Mode, with_mode: bool) -> display.List {
	list: display.List
	list.count = 1
	display.set_name(&list.items[0], "Display 1")
	if with_mode {
		display.set_desktop(&list.items[0], mode)
	}
	return list
}
