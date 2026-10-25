#+vet explicit-allocators
#+vet !unused-procedures // the renderer and frame tests call this API; the game binary does not
package ui

PALETTE_COLUMNS :: 6
PALETTE_ROWS :: 2
PALETTE_SLOTS :: PALETTE_COLUMNS * PALETTE_ROWS
PALETTE_CARD_SIZE :: 72.0
PALETTE_PANEL_WIDTH :: 678.0
PALETTE_PANEL_HEIGHT :: 226.0

Palette_Layout :: struct {
	target:     [2]f32,
	panel:      Rect,
	title:      Rect,
	grid:       Rect,
	cards:      [PALETTE_SLOTS]Rect,
	card_count: int,
	preview:    Rect,
	footer:     Rect,
}

// The draw and the hit test both read this one layout, so a card cannot move
// under the pointer unnoticed.
palette_layout :: proc(inputs: Layout_Inputs, item_count: int) -> Palette_Layout {
	layout: Palette_Layout
	layout.target = {inputs.width, inputs.height}
	padding := inputs.spacing.lg
	gap := inputs.spacing.xs

	panel_width := PALETTE_PANEL_WIDTH * inputs.density
	panel_height := PALETTE_PANEL_HEIGHT * inputs.density
	panel_x := (inputs.width - panel_width) * 0.5
	panel_y := inputs.height - inputs.spacing.xl - panel_height
	if panel_y + panel_height > inputs.height - inputs.spacing.md {
		panel_y = inputs.height - inputs.spacing.md - panel_height
	}
	panel_y = max(panel_y, inputs.spacing.md)
	layout.panel = {panel_x, panel_y, panel_width, panel_height}

	inner_x := panel_x + padding
	inner_y := panel_y + padding
	inner_width := panel_width - padding * 2
	inner_height := panel_height - padding * 2
	title_height := inputs.metrics.line_height(inputs.metrics.ctx, .Caption_Caps)
	footer_height := inputs.metrics.line_height(inputs.metrics.ctx, .Caption)
	grid_y := inner_y + title_height + gap
	grid_width := PALETTE_CARD_SIZE * inputs.density * PALETTE_COLUMNS +
		gap * f32(PALETTE_COLUMNS - 1)
	grid_height := PALETTE_CARD_SIZE * inputs.density * PALETTE_ROWS +
		gap * f32(PALETTE_ROWS - 1)

	layout.title = {inner_x, inner_y, grid_width, title_height}
	layout.grid = {inner_x, grid_y, grid_width, grid_height}
	layout.footer = {
		inner_x,
		inner_y + inner_height - footer_height,
		inner_width,
		footer_height,
	}

	preview_x := inner_x + grid_width + inputs.spacing.lg
	layout.preview = {
		preview_x,
		inner_y,
		inner_x + inner_width - preview_x,
		inner_height - footer_height - gap,
	}

	card_size := PALETTE_CARD_SIZE * inputs.density
	for index in 0 ..< PALETTE_SLOTS {
		column := index % PALETTE_COLUMNS
		row := index / PALETTE_COLUMNS
		layout.cards[index] = {
			inner_x + f32(column) * (card_size + gap),
			grid_y + f32(row) * (card_size + gap),
			card_size,
			card_size,
		}
	}
	layout.card_count = clamp(item_count, 0, PALETTE_SLOTS)
	return layout
}

palette_card_at :: proc(layout: Palette_Layout, pointer: [2]f32) -> int {
	if !rect_contains(layout.panel, pointer.x, pointer.y) {
		return -1
	}
	for index in 0 ..< layout.card_count {
		if rect_contains(layout.cards[index], pointer.x, pointer.y) {
			return index
		}
	}
	return -1
}

rect_contains :: proc(rect: Rect, x, y: f32) -> bool {
	return x >= rect.x &&
	       x < rect.x + rect.width &&
	       y >= rect.y &&
	       y < rect.y + rect.height
}
