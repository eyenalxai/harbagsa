#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:math"
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
	testing.expect(t, scene.hud.menu_open, "menu flag was dropped")
	testing.expect_value(t, scene.hud.menu.title, game.MENU_TITLE)
	testing.expect_value(t, scene.hud.menu.note, game.MENU_NOTE)
	testing.expect_value(t, len(scene.hud.menu.rows), game.MENU_ROW_COUNT)
	testing.expect_value(t, scene.hud.menu.rows[1].label, "Display")
	testing.expect_value(t, scene.hud.menu.rows[1].value, "Display 1")
	testing.expect_value(t, scene.hud.menu.rows[2].value, "1920×1080")
	testing.expect_value(t, scene.hud.menu.selected, game.MENU_ITEM_ROWS[0])
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
	testing.expect(t, scene.hud.menu_open, "menu flag was dropped")
}

@(test)
menu_slider_track_stays_inside_the_panel :: proc(t: ^testing.T) {
	sim, _, hud, _ := create_state(t)
	defer game.simulation_destroy(&sim)
	hud.menu.displays = display.fallback_list()
	game.menu_open(&hud.menu)
	game.menu_select(&hud.menu, 3)
	game.menu_view(&hud.menu, sim.settings, false)

	overlay, ok := build_menu_overlay(t, hud.menu.view)
	testing.expect(t, ok, "the menu did not build")
	if !ok {
		return
	}
	defer destroy_overlay_scratch(&overlay)

	panel := widest_quad(overlay, overlay.theme.surface_menu)
	slider := overlay.menu_slider
	padding := overlay.theme.spacing.xl
	knob := overlay.theme.spacing.md
	expected_track := panel.width - padding * 2
	travel := slider.width - knob

	testing.expect(t, slider.width > 0, "the slider has no track")
	testing.expectf(
		t,
		math.abs(slider.width - expected_track) < 0.01,
		"the track is %v, expected %v",
		slider.width,
		expected_track,
	)
	testing.expectf(t, math.abs(slider.knob - knob) < 0.01, "the knob is %v, expected %v", slider.knob, knob)
	testing.expect(t, travel > 0, "the slider has no travel")
	testing.expect(t, slider.x >= panel.x + padding, "the track starts outside the panel")
	testing.expect(
		t,
		slider.x + slider.width <= panel.x + panel.width - padding + 0.01,
		"the track runs past the panel",
	)
	testing.expect(
		t,
		slider.y >= panel.y && slider.y + slider.height <= panel.y + panel.height,
		"the track leaves the panel",
	)
}
