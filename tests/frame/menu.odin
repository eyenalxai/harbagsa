#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:math"
import "core:testing"

import "src:display"
import "src:frame"
import "src:game"
import "src:renderer"

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
blocked_row_keeps_its_band_and_draws_the_value_secondary :: proc(t: ^testing.T) {
	sim, _, hud, _ := create_state(t)
	defer game.simulation_destroy(&sim)
	hud.menu.displays = display.fallback_list()
	hud.menu.displays.count = 1
	game.menu_open(&hud.menu)
	game.menu_select(&hud.menu, 1)
	game.menu_view(&hud.menu, sim.settings, false, 0)

	row := hud.menu.view.rows[1]
	testing.expect(t, row.blocked, "the Display row is not blocked")
	testing.expect_value(t, hud.menu.view.selected, game.MENU_ITEM_ROWS[1])

	overlay, ok := build_menu_overlay(t, hud.menu.view)
	testing.expect(t, ok, "the menu did not build")
	if !ok {
		return
	}
	defer destroy_overlay_scratch(&overlay)

	band := widest_quad(overlay, overlay.theme.surface_raised)
	testing.expect(t, band.width > 0, "the blocked row lost its selection band")
	style := renderer.row_value_style(overlay.theme, row)
	testing.expect_value(t, style.color, overlay.theme.text_secondary)
	testing.expect(t, style.color != overlay.theme.text_tertiary, "the value uses tertiary")

	theme := overlay.theme
	panel := widest_quad(overlay, theme.surface_menu)
	testing.expect(t, panel.width > 0, "the panel is missing")
	layout := renderer.rows_measure(
		&overlay.atlas,
		theme,
		hud.menu.view.rows,
		{value_align = .Right},
	)
	value_x := panel.x + theme.spacing.xl + theme.spacing.sm + layout.value_column

	secondary: [256]Rect
	secondary_count := quads_from_x(overlay, theme.text_secondary, value_x, secondary[:])
	secondary_in_band := 0
	for quad in secondary[:secondary_count] {
		if quad.y < band.y + band.height && quad.y + quad.height > band.y {
			secondary_in_band += 1
		}
	}
	testing.expectf(
		t,
		secondary_in_band > 0,
		"the blocked value does not draw in secondary at or right of x %v",
		value_x,
	)

	tertiary: [256]Rect
	tertiary_count := quads_from_x(overlay, theme.text_tertiary, value_x, tertiary[:])
	tertiary_in_band := 0
	for quad in tertiary[:tertiary_count] {
		if quad.y < band.y + band.height && quad.y + quad.height > band.y {
			tertiary_in_band += 1
		}
	}
	testing.expectf(
		t,
		tertiary_in_band == 0,
		"%d quads at the blocked value column draw in tertiary",
		tertiary_in_band,
	)
}

@(test)
menu_slider_track_stays_inside_the_panel :: proc(t: ^testing.T) {
	sim, _, hud, _ := create_state(t)
	defer game.simulation_destroy(&sim)
	hud.menu.displays = display.fallback_list()
	game.menu_open(&hud.menu)
	game.menu_select(&hud.menu, 3)
	game.menu_view(&hud.menu, sim.settings, false, 0)

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
