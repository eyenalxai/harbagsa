#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:testing"

import "src:renderer"

@(test)
palette_hit_test_separates_panel_and_cards :: proc(t: ^testing.T) {
	state := renderer.Renderer {
		target = {config = {width = 800, height = 600}},
	}
	layout := renderer.palette_layout(renderer.ui_theme_init(600), 800, 600, 8)

	card := layout.cards[2]
	card_point := [2]f32 {
		(card.x + card.width * 0.5) / 800.0,
		(card.y + card.height * 0.5) / 600.0,
	}
	hit := renderer.palette_hit_test(&state, card_point, 8)
	testing.expect(t, hit.inside, "a card must be inside the panel")
	testing.expect_value(t, hit.card, 2)

	empty := layout.cards[11]
	empty_point := [2]f32 {
		(empty.x + empty.width * 0.5) / 800.0,
		(empty.y + empty.height * 0.5) / 600.0,
	}
	hit = renderer.palette_hit_test(&state, empty_point, 8)
	testing.expect(t, hit.inside, "an empty cell is still inside the panel")
	testing.expect_value(t, hit.card, -1)

	preview_point := [2]f32 {
		(layout.preview.x + layout.preview.width * 0.5) / 800.0,
		(layout.preview.y + layout.preview.height * 0.5) / 600.0,
	}
	hit = renderer.palette_hit_test(&state, preview_point, 8)
	testing.expect(t, hit.inside, "the preview is inside the panel")
	testing.expect_value(t, hit.card, -1)

	hit = renderer.palette_hit_test(&state, {0, 0}, 8)
	testing.expect(t, !hit.inside, "the window origin is outside the panel")
	testing.expect_value(t, hit.card, -1)

	hit = renderer.palette_hit_test(&state, {1, 1}, 8)
	testing.expect(t, !hit.inside, "the window edge is outside the panel")
	testing.expect_value(t, hit.card, -1)
}
