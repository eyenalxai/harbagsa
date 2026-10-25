#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:testing"

import "src:renderer"
import "src:ui"

palette_geometry :: proc(
	theme: renderer.UI_Theme,
	width, height: f32,
	item_count: int,
) -> ui.Palette_Layout {
	ctx: renderer.Layout_Context
	renderer.layout_context_init(&ctx, theme, nil, width, height)
	return ui.palette_layout(ctx.inputs, item_count)
}

@(test)
palette_cards_form_a_six_by_two_grid :: proc(t: ^testing.T) {
	theme := renderer.ui_theme_init(720)
	layout := palette_geometry(theme, 1280, 720, 11)

	testing.expect_value(t, layout.card_count, 11)
	testing.expect_value(t, layout.panel.width, ui.PALETTE_PANEL_WIDTH)
	testing.expect_value(t, layout.panel.height, ui.PALETTE_PANEL_HEIGHT)
	testing.expect_value(t, layout.panel.x, (1280.0 - layout.panel.width) * 0.5)
	testing.expect_value(t, layout.panel.y, 720.0 - theme.spacing.xl - layout.panel.height)

	card_size := ui.PALETTE_CARD_SIZE * theme.density
	gap := theme.spacing.xs
	for index in 0 ..< ui.PALETTE_SLOTS {
		card := layout.cards[index]
		testing.expect_value(t, card.width, card_size)
		testing.expect_value(t, card.height, card_size)
	}
	testing.expect_value(t, layout.cards[1].x, layout.cards[0].x + card_size + gap)
	testing.expect_value(t, layout.cards[6].x, layout.cards[0].x)
	testing.expect_value(t, layout.cards[6].y, layout.cards[0].y + card_size + gap)
	testing.expect(
		t,
		layout.grid.width == card_size * ui.PALETTE_COLUMNS + gap * f32(ui.PALETTE_COLUMNS - 1),
		"the grid is not six cards plus five gaps",
	)
	testing.expect(
		t,
		layout.grid.height == card_size * ui.PALETTE_ROWS + gap * f32(ui.PALETTE_ROWS - 1),
		"the grid is not two cards plus one gap",
	)
}

