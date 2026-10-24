#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import "src:display"
import "src:ui"
import game "src:game"

@(test)
settings_start_with_the_documented_defaults :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	testing.expect_value(t, sim.settings.window.mode, display.Window_Mode.Borderless)
	testing.expect_value(t, sim.settings.window.display, 0)
	testing.expect_value(t, sim.settings.window.resolution, display.Mode{1280, 720})
	testing.expect_value(t, sim.settings.sprint_mode, game.Input_Mode.Hold)
	testing.expect_value(t, sim.settings.crouch_mode, game.Input_Mode.Toggle)
	testing.expect_value(t, sim.settings.prone_mode, game.Input_Mode.Toggle)
	testing.expect_value(t, game.input_mode_name(.Hold), "Hold")
	testing.expect_value(t, game.input_mode_name(.Toggle), "Toggle")
	testing.expect_value(t, game.window_mode_name(.Borderless), "Borderless")
	testing.expect_value(t, game.window_mode_name(.Windowed), "Windowed")
	testing.expect_value(t, game.settings_default().crouch_mode, game.Input_Mode.Toggle)
}

@(test)
player_reset_keeps_the_settings :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	sim.settings.window.mode = .Windowed
	sim.settings.window.display = 1
	sim.settings.window.resolution = {1600, 900}
	sim.settings.sprint_mode = .Toggle
	sim.settings.crouch_mode = .Hold
	sim.settings.prone_mode = .Hold

	game.simulation_reset(&sim)

	testing.expect_value(t, sim.settings.window.mode, display.Window_Mode.Windowed)
	testing.expect_value(t, sim.settings.window.display, 1)
	testing.expect_value(t, sim.settings.window.resolution, display.Mode{1600, 900})
	testing.expect_value(t, sim.settings.sprint_mode, game.Input_Mode.Toggle)
	testing.expect_value(t, sim.settings.crouch_mode, game.Input_Mode.Hold)
	testing.expect_value(t, sim.settings.prone_mode, game.Input_Mode.Hold)
}

@(test)
menu_opens_moves_and_closes :: proc(t: ^testing.T) {
	menu: game.Menu_State
	testing.expect(t, !menu.open, "menu starts open")

	game.menu_open(&menu)
	testing.expect(t, menu.open, "menu did not open")
	game.menu_move(&menu, -1)
	testing.expect_value(t, menu.selected, game.Menu_Item.Resume)
	game.menu_move(&menu, 1)
	testing.expect_value(t, menu.selected, game.Menu_Item.Window_Mode)
	game.menu_select(&menu, 2)
	testing.expect_value(t, menu.selected, game.Menu_Item.Resolution)
	testing.expect_value(t, game.menu_selected_name(&menu), "Resolution")
	game.menu_select(&menu, 5)
	testing.expect_value(t, menu.selected, game.Menu_Item.Prone)
	testing.expect_value(t, game.menu_selected_name(&menu), "Prone mode")

	game.menu_close(&menu)
	testing.expect(t, !menu.open, "menu did not close")
}

@(test)
menu_activation_changes_the_input_modes :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	menu: game.Menu_State
	game.menu_open(&menu)

	game.menu_select(&menu, 3)
	testing.expect(t, !game.menu_activate(&menu, &sim.settings), "a setting closed the menu")
	testing.expect_value(t, sim.settings.sprint_mode, game.Input_Mode.Toggle)

	game.menu_select(&menu, 4)
	testing.expect(t, !game.menu_activate(&menu, &sim.settings), "a setting closed the menu")
	testing.expect_value(t, sim.settings.crouch_mode, game.Input_Mode.Hold)

	game.menu_select(&menu, 5)
	_ = game.menu_change_setting(&menu, &sim.settings, 1)
	testing.expect_value(t, sim.settings.prone_mode, game.Input_Mode.Hold)

	game.menu_select(&menu, 6)
	testing.expect(t, game.menu_activate(&menu, &sim.settings), "Resume did not close the menu")
	testing.expect(t, !menu.open, "Resume left the menu open")
}

@(test)
menu_changes_the_window_mode :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	menu: game.Menu_State
	menu.displays = display.fallback_list()
	game.menu_open(&menu)
	game.menu_select(&menu, 0)

	_ = game.menu_change_setting(&menu, &sim.settings, 1)
	testing.expect_value(t, sim.settings.window.mode, display.Window_Mode.Windowed)
	_ = game.menu_change_setting(&menu, &sim.settings, 1)
	testing.expect_value(t, sim.settings.window.mode, display.Window_Mode.Borderless)
}

@(test)
resolution_starts_a_window_from_borderless :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	menu: game.Menu_State
	menu.displays = display.fallback_list()
	game.menu_open(&menu)
	game.menu_select(&menu, 2)

	_ = game.menu_change_setting(&menu, &sim.settings, 1)

	testing.expect_value(t, sim.settings.window.mode, display.Window_Mode.Windowed)
	testing.expect_value(t, sim.settings.window.resolution, display.Mode{1600, 900})
}

@(test)
resolution_cycles_in_the_pressed_direction :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	sim.settings.window.mode = .Windowed
	menu: game.Menu_State
	menu.displays = display.fallback_list()
	game.menu_open(&menu)
	game.menu_select(&menu, 2)

	_ = game.menu_change_setting(&menu, &sim.settings, 1)
	testing.expect_value(t, sim.settings.window.resolution, display.Mode{1920, 1080})
	_ = game.menu_change_setting(&menu, &sim.settings, -1)
	testing.expect_value(t, sim.settings.window.resolution, display.Mode{1280, 720})
}

@(test)
display_change_snaps_the_resolution :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	sim.settings.window.mode = .Windowed
	sim.settings.window.resolution = {1600, 900}
	menu: game.Menu_State
	menu.displays = display.fallback_list()
	game.menu_open(&menu)
	game.menu_select(&menu, 1)

	_ = game.menu_change_setting(&menu, &sim.settings, 1)

	testing.expect_value(t, sim.settings.window.display, 1)
	testing.expect_value(t, sim.settings.window.resolution, display.Mode{1280, 720})
}

@(test)
menu_reset_keeps_the_display_snapshot :: proc(t: ^testing.T) {
	menu: game.Menu_State
	menu.displays = display.fallback_list()
	game.menu_open(&menu)

	game.menu_reset(&menu)

	testing.expect(t, !menu.open, "menu reset left the menu open")
	testing.expect_value(t, menu.displays.count, 2)
	testing.expect_value(t, display.name(display.info_at(&menu.displays, 1)), "Display 2")
}

@(test)
toggle_sprint_stays_on_without_a_held_key :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	sim.settings.sprint_mode = .Toggle

	step(&sim, game.Input_Snapshot{move_forward = 1.0, sprint_pressed = true}, 1)
	testing.expect_value(t, sim.player.gait, game.Gait.Sprint)

	step(&sim, game.Input_Snapshot{move_forward = 1.0}, 5)
	testing.expect_value(t, sim.player.gait, game.Gait.Sprint)

	step(&sim, game.Input_Snapshot{move_forward = 1.0, sprint_pressed = true}, 1)
	testing.expect_value(t, sim.player.gait, game.Gait.Walk)
}

@(test)
hold_crouch_releases_when_the_key_is_up :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	sim.settings.crouch_mode = .Hold

	step(&sim, game.Input_Snapshot{crouch_pressed = true, crouch_held = true}, 1)
	testing.expect_value(t, sim.player.stance, game.Stance.Crouching)
	step(&sim, {}, 5)
	testing.expect_value(t, sim.player.stance, game.Stance.Standing)
}

@(test)
hold_prone_releases_when_the_key_is_up :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	sim.settings.prone_mode = .Hold
	step(&sim, {}, 10)

	step(&sim, game.Input_Snapshot{prone_pressed = true, prone_held = true}, 1)
	testing.expect_value(t, sim.player.stance, game.Stance.Prone)
	step(&sim, {}, 5)
	testing.expect_value(t, sim.player.stance, game.Stance.Standing)
}

@(test)
menu_view_lists_the_settings_and_controls :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	menu: game.Menu_State
	menu.displays = display.fallback_list()
	game.menu_open(&menu)
	game.menu_view(&menu, sim.settings, false)

	rows := menu.view.rows
	testing.expect_value(t, len(rows), game.MENU_ROW_COUNT)
	testing.expect_value(t, rows[0].kind, ui.Row_Kind.Setting)
	testing.expect_value(t, rows[0].label, "Window mode")
	testing.expect_value(t, rows[0].value, "Borderless")
	testing.expect_value(t, rows[1].value, "Display 1")
	testing.expect_value(t, rows[2].value, "1920×1080")
	testing.expect(t, rows[2].numeric, "the resolution is a number")
	testing.expect_value(t, rows[3].value, "Hold")
	testing.expect_value(t, rows[4].value, "Toggle")
	testing.expect_value(t, rows[5].value, "Toggle")
	testing.expect_value(t, rows[game.MENU_ROW_DIVIDER].kind, ui.Row_Kind.Divider)
	testing.expect_value(t, rows[game.MENU_ROW_RESUME].kind, ui.Row_Kind.Action)
	testing.expect_value(t, rows[game.MENU_ROW_RESUME].label, "Resume")
	testing.expect_value(t, rows[game.MENU_ROW_HEADER].kind, ui.Row_Kind.Header)
	testing.expect_value(t, rows[game.MENU_ROW_HEADER].label, "Controls")
	testing.expect_value(t, menu.view.selected, game.MENU_ITEM_ROWS[0])
	testing.expect_value(t, len(menu.view.hints), game.MENU_HINT_COUNT)
	testing.expect_value(t, menu.view.hints[0].keys, "WASD")
	testing.expect_value(t, menu.view.hints[0].action, "move")
	testing.expect_value(t, menu.view.hints[14].keys, "F4")
	testing.expect_value(t, menu.view.hints[14].action, "perf")

	game.menu_view(&menu, sim.settings, true)
	testing.expect_value(t, menu.view.hints[0].keys, "WASD")
	testing.expect_value(t, menu.view.hints[0].action, "fly")
}
