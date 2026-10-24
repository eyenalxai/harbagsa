#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:testing"

import "src:display"
import "src:frame"
import "src:game"

@(test)
menu_maps_to_the_hud :: proc(t: ^testing.T) {
	sim, debug, hud, scratch := create_state(t)
	defer game.simulation_destroy(&sim)
	hud.menu.displays = display.fallback_list()
	game.menu_open(&hud.menu)

	scene := frame.build(
		&sim,
		&debug,
		{alpha = 1.0, captured = false, hud = true},
		nil,
		&hud,
		&scratch,
	)
	testing.expect(t, scene.hud.enabled, "menu did not enable the HUD")
	testing.expect(t, scene.hud.menu.open, "menu flag was dropped")
	testing.expect_value(t, scene.hud.menu.title, game.MENU_TITLE)
	testing.expect_value(t, scene.hud.menu.note, game.MENU_NOTE)
	testing.expect_value(t, len(scene.hud.menu.lines), 14)
	testing.expect_value(t, scene.hud.menu.lines[1], "Display      Display 1")
	testing.expect_value(t, scene.hud.menu.lines[2], "Resolution   1920x1080")
	testing.expect_value(t, scene.hud.menu.selected, 0)
}

@(test)
menu_renders_without_the_hud_flag :: proc(t: ^testing.T) {
	sim, debug, hud, scratch := create_state(t)
	defer game.simulation_destroy(&sim)
	hud.menu.displays = display.fallback_list()
	game.menu_open(&hud.menu)

	scene := frame.build(
		&sim,
		&debug,
		{alpha = 1.0, captured = false, hud = false},
		nil,
		&hud,
		&scratch,
	)
	testing.expect(t, scene.hud.enabled, "menu needs the HUD overlay")
	testing.expect(t, scene.hud.menu.open, "menu flag was dropped")
}
