#+vet explicit-allocators
#+vet !unused-procedures // the frame tests call the panel bounds
package renderer

PALETTE_COLUMNS :: 6
PALETTE_ROWS :: 2
PALETTE_SLOTS :: PALETTE_COLUMNS * PALETTE_ROWS
PALETTE_CARD_SIZE :: 72.0
PALETTE_PANEL_WIDTH :: 678.0
PALETTE_PANEL_HEIGHT :: 226.0

HUD_Rect :: struct {
	x:      f32,
	y:      f32,
	width:  f32,
	height: f32,
}

Palette_Layout :: struct {
	target:     [2]f32,
	panel:      HUD_Rect,
	title:      HUD_Rect,
	grid:       HUD_Rect,
	cards:      [PALETTE_SLOTS]HUD_Rect,
	card_count: int,
	preview:    HUD_Rect,
	footer:     HUD_Rect,
}

// The draw and the hit test both read this one layout, so a card cannot move
// under the pointer unnoticed.
palette_layout :: proc(theme: UI_Theme, width, height: f32, item_count: int) -> Palette_Layout {
	layout: Palette_Layout
	layout.target = {width, height}
	density := theme.density
	padding := theme.spacing.lg
	gap := theme.spacing.xs

	panel_width := PALETTE_PANEL_WIDTH * density
	panel_height := PALETTE_PANEL_HEIGHT * density
	panel_x := (width - panel_width) * 0.5
	panel_y := height - theme.spacing.xl - panel_height
	if panel_y + panel_height > height - theme.spacing.md {
		panel_y = height - theme.spacing.md - panel_height
	}
	panel_y = max(panel_y, theme.spacing.md)
	layout.panel = {panel_x, panel_y, panel_width, panel_height}

	inner_x := panel_x + padding
	inner_y := panel_y + padding
	inner_width := panel_width - padding * 2
	inner_height := panel_height - padding * 2
	title_height := theme.type_caption_caps.line_height
	footer_height := theme.type_caption.line_height
	grid_y := inner_y + title_height + gap
	grid_width := PALETTE_CARD_SIZE * density * PALETTE_COLUMNS +
		gap * f32(PALETTE_COLUMNS - 1)
	grid_height := PALETTE_CARD_SIZE * density * PALETTE_ROWS +
		gap * f32(PALETTE_ROWS - 1)

	layout.title = {inner_x, inner_y, grid_width, title_height}
	layout.grid = {inner_x, grid_y, grid_width, grid_height}
	layout.footer = {
		inner_x,
		inner_y + inner_height - footer_height,
		inner_width,
		footer_height,
	}

	preview_x := inner_x + grid_width + theme.spacing.lg
	layout.preview = {
		preview_x,
		inner_y,
		inner_x + inner_width - preview_x,
		inner_height - footer_height - gap,
	}

	card_size := PALETTE_CARD_SIZE * density
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

palette_panel_bounds :: proc(theme: UI_Theme, width, height: f32) -> HUD_Rect {
	return palette_layout(theme, width, height, 0).panel
}

palette_card_at :: proc(layout: Palette_Layout, pointer: [2]f32) -> int {
	x := pointer.x * layout.target.x
	y := pointer.y * layout.target.y
	if !hud_rect_contains(layout.panel, x, y) {
		return -1
	}
	for index in 0 ..< layout.card_count {
		if hud_rect_contains(layout.cards[index], x, y) {
			return index
		}
	}
	return -1
}

Palette_Hit :: struct {
	inside: bool,
	card:   int,
}

// The game loop asks the renderer where a normalized pointer lands. The layout
// and the hit test stay in one package, so a card cannot move under the pointer
// unnoticed.
palette_hit_test :: proc(r: ^Renderer, pointer: [2]f32, item_count: int) -> Palette_Hit {
	width := f32(r.target.config.width)
	height := f32(r.target.config.height)
	layout := palette_layout(ui_theme_init(r.target.config.height), width, height, item_count)
	x := pointer.x * width
	y := pointer.y * height
	return {
		inside = hud_rect_contains(layout.panel, x, y),
		card = palette_card_at(layout, pointer),
	}
}

hud_rect_contains :: proc(rect: HUD_Rect, x, y: f32) -> bool {
	return x >= rect.x &&
	       x < rect.x + rect.width &&
	       y >= rect.y &&
	       y < rect.y + rect.height
}
