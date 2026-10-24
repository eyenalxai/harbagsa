#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import game "src:game"

@(test)
settings_start_with_the_documented_defaults :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	testing.expect_value(t, sim.settings.sprint_mode, game.Input_Mode.Hold)
	testing.expect_value(t, sim.settings.crouch_mode, game.Input_Mode.Toggle)
	testing.expect_value(t, sim.settings.prone_mode, game.Input_Mode.Toggle)
	testing.expect_value(t, game.input_mode_name(.Hold), "Hold")
	testing.expect_value(t, game.input_mode_name(.Toggle), "Toggle")
	testing.expect_value(t, game.settings_default().crouch_mode, game.Input_Mode.Toggle)
}

@(test)
player_reset_keeps_the_settings :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	sim.settings.sprint_mode = .Toggle
	sim.settings.crouch_mode = .Hold
	sim.settings.prone_mode = .Hold

	game.simulation_reset(&sim)

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
	testing.expect_value(t, menu.selected, game.Menu_Item.Sprint)
	game.menu_select(&menu, 2)
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

	game.menu_select(&menu, 0)
	testing.expect(t, !game.menu_activate(&menu, &sim.settings), "a setting closed the menu")
	testing.expect_value(t, sim.settings.sprint_mode, game.Input_Mode.Toggle)

	game.menu_select(&menu, 1)
	testing.expect(t, !game.menu_activate(&menu, &sim.settings), "a setting closed the menu")
	testing.expect_value(t, sim.settings.crouch_mode, game.Input_Mode.Hold)

	game.menu_select(&menu, 2)
	_ = game.menu_toggle_setting(&menu, &sim.settings)
	testing.expect_value(t, sim.settings.prone_mode, game.Input_Mode.Hold)

	game.menu_select(&menu, 3)
	testing.expect(t, game.menu_activate(&menu, &sim.settings), "Resume did not close the menu")
	testing.expect(t, !menu.open, "Resume left the menu open")
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
	game.menu_open(&menu)
	game.menu_view(&menu, sim.settings, false)

	testing.expect_value(t, menu.text.count, 11)
	testing.expect_value(t, menu.text.lines[0], "Sprint mode  Hold")
	testing.expect_value(t, menu.text.lines[1], "Crouch mode  Toggle")
	testing.expect_value(t, menu.text.lines[2], "Prone mode   Toggle")
	testing.expect_value(t, menu.text.lines[3], "Resume")
	testing.expect_value(t, menu.text.lines[5], "Controls")
	testing.expect_value(t, menu.text.lines[10], "F2 debug mode    F3 TAA    Esc settings")

	game.menu_view(&menu, sim.settings, true)
	testing.expect_value(t, menu.text.lines[6], "WASD fly    Space up    Ctrl down")
}
