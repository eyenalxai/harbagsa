#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:strings"
import "core:testing"

import "src:frame"
import "src:game"
import "src:renderer"
import "src:ui"

@(test)
frame_fills_the_palette_from_the_prefab_catalog :: proc(t: ^testing.T) {
	sim, debug, hud, scratch := create_state(t)
	defer game.simulation_destroy(&sim)
	debug.active = true
	apply_expect(t, &debug, &sim, game.Palette_Open{}, "open failed")
	apply_expect(t, &debug, &sim, game.Palette_Select{index = 4}, "select failed")

	scene := frame.build(
		&sim,
		&debug,
		{alpha = 1.0, captured = false, hud = true},
		nil,
		&hud,
		&scratch,
	)
	palette := scene.hud.palette
	testing.expect(t, palette.open, "the palette is not open")
	testing.expect_value(t, palette.item_count, game.PREFAB_COUNT)
	testing.expect_value(t, palette.selected, 4)
	testing.expect_value(t, palette.items[4].name, "Platform")
	testing.expect_value(t, palette.items[4].short_name, "Platform")
	testing.expect_value(t, palette.items[4].body, "static")
	testing.expect_value(t, palette.items[4].key, "5")
	testing.expect_value(t, palette.body, "static")
	testing.expect_value(t, string(palette.count[:palette.count_length]), "3 / 128")
	testing.expect(
		t,
		strings.contains(string(palette.size[:palette.size_length]), "4.0 × 0.5 × 4.0 m"),
		"the size line is missing",
	)
	testing.expect(t, .Palette in scene.view_flags, "the palette view flag is missing")
	testing.expect(t, !(.Capture_Hint in scene.view_flags), "the capture hint survived the palette")
}

@(test)
frame_fills_the_lamp_light_line_and_emissive_thumbnail :: proc(t: ^testing.T) {
	sim, debug, hud, scratch := create_state(t)
	defer game.simulation_destroy(&sim)
	debug.active = true
	apply_expect(t, &debug, &sim, game.Palette_Open{}, "open failed")
	lamp_index := int(game.Prefab_Id.Lamp)
	apply_expect(t, &debug, &sim, game.Palette_Select{index = lamp_index}, "select failed")

	scene := frame.build(
		&sim,
		&debug,
		{alpha = 1.0, captured = false, hud = true},
		nil,
		&hud,
		&scratch,
	)
	item := scene.hud.palette.items[lamp_index]
	testing.expect(t, item.emissive, "the lamp card is not emissive")
	testing.expect_value(t, string(item.light_line[:item.light_length]), "warm · 1.5 · 8 m")
	testing.expect_value(t, scene.hud.palette.hint_count, len(game.PALETTE_HINTS) + 1)

	apply_expect(t, &debug, &sim, game.Light_Adjust{change = .Color}, "colour failed")
	apply_expect(t, &debug, &sim, game.Light_Adjust{change = .Intensity_Up}, "intensity failed")
	apply_expect(t, &debug, &sim, game.Light_Adjust{change = .Range_Up}, "range failed")
	scene = frame.build(
		&sim,
		&debug,
		{alpha = 1.0, captured = false, hud = true},
		nil,
		&hud,
		&scratch,
	)
	item = scene.hud.palette.items[lamp_index]
	testing.expect_value(t, string(item.light_line[:item.light_length]), "cool · 1.7 · 9 m")
}

@(test)
palette_needs_debug_mode_and_yields_to_the_menu :: proc(t: ^testing.T) {
	sim, debug, hud, scratch := create_state(t)
	defer game.simulation_destroy(&sim)
	debug.palette.open = true

	scene := frame.build(&sim, &debug, {alpha = 1.0, hud = true}, nil, &hud, &scratch)
	testing.expect(t, !scene.hud.palette.open, "the palette drew outside debug mode")

	debug.active = true
	apply_expect(t, &debug, &sim, game.Palette_Open{}, "open failed")
	game.menu_open(&hud.menu)
	scene = frame.build(&sim, &debug, {alpha = 1.0, hud = true}, nil, &hud, &scratch)
	testing.expect(t, scene.hud.menu_open, "the menu is not open")
	testing.expect(t, !scene.hud.palette.open, "the palette outranked the menu")
	testing.expect(t, !(.Palette in scene.view_flags), "the palette flag outranked the menu")

	palette := palette_fixture(11)
	menu_overlay := renderer.Overlay {
		theme = renderer.ui_theme_init(720),
	}
	atlas, built := build_atlas(t, menu_overlay.theme)
	testing.expect(t, built, "the atlas did not build")
	if !built {
		return
	}
	menu_overlay.atlas = atlas
	menu_overlay.hud_vertices = make([]renderer.HUD_Vertex, 24576, context.allocator)
	defer destroy_overlay_scratch(&menu_overlay)
	renderer.build_hud(
		&menu_overlay,
		1280,
		720,
		renderer.HUD_Frame {
			enabled = true,
			menu_open = true,
			menu = ui.Menu{title = "Settings"},
			palette = palette,
		},
	)
	surfaces: [8]Rect
	testing.expect_value(
		t,
		quads_with(menu_overlay, menu_overlay.theme.surface_hud, surfaces[:]),
		0,
	)
}
