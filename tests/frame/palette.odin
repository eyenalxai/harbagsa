#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:testing"

import "src:game"
import "src:renderer"
import "src:ui"

PALETTE_TEST_HINTS := [5]ui.Hint_Cell {
	{keys = "1-9", action = "select"},
	{keys = "Arrows", action = "move"},
	{keys = "Enter", action = "pick"},
	{keys = "M", action = "body"},
	{keys = "Esc", action = "close"},
}

palette_fixture :: proc(filled: int) -> ui.Palette {
	palette := ui.Palette {
		open = true,
		title = "Object palette",
		item_count = filled,
		selected = 4,
		body = "static",
		hint_count = len(PALETTE_TEST_HINTS),
	}
	for index in 0 ..< filled {
		color := [4]f32{0.30, 0.60, 0.90, 1.0}
		half_extents := [3]f32{0.5, 0.5, 0.5}
		pitch: f32
		if index == 5 {
			half_extents = {1.0, 0.25, 1.5}
			pitch = game.RAMP_BASE_PITCH
		}
		item := ui.Palette_Item {
			name = "Prefab",
			short_name = "Short",
			half_extents = half_extents,
			color = color,
			base_pitch = pitch,
			body = index < 3 ? "dynamic" : "static",
			key = index < 9 ? "1" : "",
		}
		if index == 7 {
			item.light_length = write_palette_text(item.light_line[:], "warm · 1.5 · 8 m")
			item.emissive = true
		}
		palette.items[index] = item
	}
	for hint, index in PALETTE_TEST_HINTS {
		palette.hints[index] = hint
	}
	palette.size_length = write_palette_text(palette.size[:], "1.0 × 1.0 × 1.0 m")
	palette.count_length = write_palette_text(palette.count[:], "3 / 128")
	return palette
}

@(private)
write_palette_text :: proc(buffer: []u8, text: string) -> int {
	for value, index in text {
		buffer[index] = u8(value)
	}
	return len(text)
}

@(test)
palette_draws_eleven_cards_and_one_empty_cell :: proc(t: ^testing.T) {
	palette := palette_fixture(11)
	overlay, ok := build_palette_overlay(t, 1280, 720, palette)
	testing.expect(t, ok, "the palette did not build")
	defer destroy_overlay_scratch(&overlay)

	cards: [32]Rect
	count := quads_with(overlay, overlay.theme.surface_menu, cards[:])
	testing.expect_value(t, count, 10)
	selected: [8]Rect
	raised := quads_with(overlay, overlay.theme.surface_raised, selected[:])
	testing.expect_value(t, raised, 1)
	testing.expect(
		t,
		selected[0].width == 72.0 && selected[0].height == 72.0,
		"the selected cell is not a card",
	)
}

@(test)
palette_selected_card_raises_and_bars_the_leading_edge :: proc(t: ^testing.T) {
	palette := palette_fixture(11)
	overlay, ok := build_palette_overlay(t, 1280, 720, palette)
	testing.expect(t, ok, "the palette did not build")
	defer destroy_overlay_scratch(&overlay)

	theme := overlay.theme
	layout := palette_geometry(theme, 1280, 720, 11)
	card := layout.cards[palette.selected]

	raised_buffer: [4]Rect
	raised_count := quads_with(overlay, theme.surface_raised, raised_buffer[:])
	testing.expect_value(t, raised_count, 1)
	raised := raised_buffer[0]
	testing.expect(
		t,
		raised.x == card.x && raised.y == card.y,
		"the raised surface is not on the selected card",
	)
	testing.expect(
		t,
		raised.width == card.width && raised.height == card.height,
		"the raised surface is not card shaped",
	)

	bar_buffer: [4]Rect
	bar_count := quads_with(overlay, theme.accent, bar_buffer[:])
	testing.expect_value(t, bar_count, 1)
	bar := bar_buffer[0]
	testing.expect(t, bar.x == card.x, "the accent bar is not on the leading edge")
	testing.expect(t, bar.y == card.y && bar.height == card.height, "the accent bar does not span the card")
	testing.expect_value(t, bar.width, 2.0)
}

@(test)
palette_preview_projects_three_faces_back_to_front :: proc(t: ^testing.T) {
	cube := renderer.palette_project_box({0.5, 0.5, 0.5}, 0)
	testing.expect_value(t, cube.count, 3)
	testing.expect_value(t, cube.faces[0].face, renderer.Palette_Face.Right)
	testing.expect_value(t, cube.faces[1].face, renderer.Palette_Face.Front)
	testing.expect_value(t, cube.faces[2].face, renderer.Palette_Face.Top)

	ramp := renderer.palette_project_box({1.0, 0.25, 1.5}, game.RAMP_BASE_PITCH)
	testing.expect_value(t, ramp.count, 3)
	testing.expect_value(t, ramp.faces[0].face, renderer.Palette_Face.Right)
	testing.expect_value(t, ramp.faces[1].face, renderer.Palette_Face.Front)
	testing.expect_value(t, ramp.faces[2].face, renderer.Palette_Face.Top)

	flat := renderer.palette_project_box({1.0, 0.25, 1.5}, 0)
	testing.expect(
		t,
		ramp.faces[2].points[0] != flat.faces[2].points[0],
		"the ramp base pitch did not move the top face",
	)
	testing.expect(
		t,
		cube.faces[0].shade != cube.faces[1].shade && cube.faces[1].shade != cube.faces[2].shade,
		"the three faces do not have three shades",
	)
}

@(test)
palette_fits_800x600_and_clears_the_crosshair :: proc(t: ^testing.T) {
	theme := renderer.ui_theme_init(600)
	layout := palette_geometry(theme, 800, 600, 11)
	testing.expect_value(t, layout.panel.x, 61.0)
	testing.expect_value(t, layout.panel.y, 358.0)
	testing.expect(
		t,
		layout.panel.y >= theme.spacing.md,
		"the panel top is not clamped to the top margin",
	)
	testing.expect(
		t,
		layout.panel.y + layout.panel.height <= 600.0,
		"the panel clips the bottom edge",
	)

	palette := palette_fixture(11)
	overlay, ok := build_palette_overlay(t, 800, 600, palette)
	testing.expect(t, ok, "the palette did not build")
	defer destroy_overlay_scratch(&overlay)

	crosshair := bounds_of(overlay, theme.crosshair)
	testing.expect(t, crosshair.width > 0 && crosshair.height > 0, "the crosshair is missing")
	panel := Rect{layout.panel.x, layout.panel.y, layout.panel.width, layout.panel.height}
	testing.expect(
		t,
		!rects_overlap(panel, crosshair),
		"the palette overlaps the crosshair at 800x600",
	)
}

@(test)
palette_hides_the_capture_hint :: proc(t: ^testing.T) {
	palette := palette_fixture(11)
	overlay, ok := build_palette_overlay(t, 1280, 720, palette)
	testing.expect(t, ok, "the palette did not build")
	defer destroy_overlay_scratch(&overlay)

	surfaces: [8]Rect
	count := quads_with(overlay, overlay.theme.surface_hud, surfaces[:])
	testing.expect_value(t, count, 1)
	layout := palette_geometry(overlay.theme, 1280, 720, 11)
	testing.expect(
		t,
		surfaces[0].x == layout.panel.x && surfaces[0].width == layout.panel.width,
		"the surface is not the palette",
	)
}

@(test)
palette_hit_test_matches_the_draw_and_skips_the_empty_slot :: proc(t: ^testing.T) {
	theme := renderer.ui_theme_init(720)
	layout := palette_geometry(theme, 800, 600, 11)
	for index in 0 ..< layout.card_count {
		card := layout.cards[index]
		pointer := [2]f32 {
			card.x + card.width * 0.5,
			card.y + card.height * 0.5,
		}
		testing.expectf(
			t,
			ui.palette_card_at(layout, pointer) == index,
			"card %d did not hit its own rectangle",
			index,
		)
	}

	empty := layout.cards[ui.PALETTE_SLOTS - 1]
	empty_pointer := [2]f32 {
		empty.x + empty.width * 0.5,
		empty.y + empty.height * 0.5,
	}
	testing.expect_value(t, ui.palette_card_at(layout, empty_pointer), -1)

	gap_pointer := [2]f32 {
		layout.cards[0].x + layout.cards[0].width + 1.0,
		layout.cards[0].y + layout.cards[0].height * 0.5,
	}
	testing.expect_value(t, ui.palette_card_at(layout, gap_pointer), -1)
	testing.expect_value(t, ui.palette_card_at(layout, {0.0, 0.0}), -1)
	testing.expect_value(t, ui.palette_card_at(layout, {799.0, 599.0}), -1)
	testing.expect(
		t,
		palette_geometry(theme, 800, 600, 0).panel == layout.panel,
		"the panel bounds moved",
	)
}

@(private)
build_palette_overlay :: proc(
	t: ^testing.T,
	width, height: f32,
	palette: ui.Palette,
) -> (overlay: renderer.Overlay, ok: bool) {
	overlay.theme = renderer.ui_theme_init(u32(height))
	atlas, built := build_atlas(t, overlay.theme)
	testing.expect(t, built, "the atlas did not build")
	if !built {
		return {}, false
	}
	overlay.atlas = atlas
	overlay.hud_vertices = make([]renderer.HUD_Vertex, 24576, context.allocator)
	renderer.build_hud(
		&overlay,
		width,
		height,
		renderer.HUD_Frame {
			enabled = true,
			capture_hint = "Click to capture mouse",
			captured = false,
			palette = palette,
		},
	)
	return overlay, true
}

@(private)
rects_overlap :: proc(a, b: Rect) -> bool {
	return a.x < b.x + b.width &&
	       b.x < a.x + a.width &&
	       a.y < b.y + b.height &&
	       b.y < a.y + a.height
}
