#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:testing"

import "src:display"
import "src:game"
import "src:renderer"
import "src:ui"

@(test)
status_panel_width_survives_a_full_sweep :: proc(t: ^testing.T) {
	sim, debug, hud, _ := create_state(t)
	defer game.simulation_destroy(&sim)

	theme := renderer.ui_theme_init(720)
	atlas, built := build_atlas(t, theme)
	testing.expect(t, built, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)
	positions := [5][3]f32{{0, 0, 14}, {-19.9, 0.1, -19.9}, {19.9, 0, 0}, {-0.1, 0, 0.1}, {9.9, 9.9, 9.9}}
	expected := measure_status_panel(t, &sim, &debug, &hud, &atlas, theme, positions[0])

	for position in positions[1:] {
		actual := measure_status_panel(t, &sim, &debug, &hud, &atlas, theme, position)
		testing.expectf(
			t,
			actual.width == expected.width,
			"the panel width moved from %v to %v at %v",
			expected.width,
			actual.width,
			position,
		)
	}
}

@(test)
menu_dividers_and_band_share_the_panel_inner_edge :: proc(t: ^testing.T) {
	sim, _, hud, _ := create_state(t)
	defer game.simulation_destroy(&sim)
	hud.menu.displays = display.fallback_list()
	game.menu_open(&hud.menu)
	game.menu_select(&hud.menu, 4)
	game.menu_view(&hud.menu, sim.settings, false)

	overlay, ok := build_menu_overlay(t, hud.menu.view)
	testing.expect(t, ok, "the menu did not build")
	defer destroy_overlay_scratch(&overlay)

	theme := overlay.theme
	panel := widest_quad(overlay, theme.surface_menu)
	testing.expect(t, panel.width > 0, "the panel is missing")

	inner_x := panel.x + theme.spacing.xl
	inner_width := panel.width - theme.spacing.xl * 2

	separators: [16]Rect
	separator_count := quads_with(overlay, theme.line_separator, separators[:])
	testing.expect(t, separator_count >= 2, "the menu needs a title rule and a row divider")
	for quad in separators[:separator_count] {
		testing.expectf(
			t,
			quad.x == inner_x && quad.width == inner_width,
			"a divider runs %v..%v, the inner edge is %v..%v",
			quad.x,
			quad.x + quad.width,
			inner_x,
			inner_x + inner_width,
		)
	}
	band := widest_quad(overlay, theme.surface_raised)
	testing.expect(t, band.width > 0, "the selection band is missing")
	testing.expectf(
		t,
		band.x == inner_x && band.width == inner_width,
		"the band is not flush with the panel's inner edge",
	)
	testing.expectf(
		t,
		band.x >= panel.x && band.x + band.width <= panel.x + panel.width,
		"the band escapes the panel",
	)
}

@(test)
capture_hint_clears_the_crosshair :: proc(t: ^testing.T) {
	theme := renderer.ui_theme_init(720)
	atlas, built := build_atlas(t, theme)
	testing.expect(t, built, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)
	overlay := renderer.Overlay {
		atlas = atlas,
		theme = theme,
	}
	overlay.hud_vertices = make([]renderer.HUD_Vertex, 4096, context.allocator)
	defer delete(overlay.hud_vertices, context.allocator)

	frame := renderer.HUD_Frame {
		enabled      = true,
		capture_hint = "Click to capture mouse",
		captured     = false,
	}
	renderer.build_hud(&overlay, 1280, 720, frame)

	hint := widest_quad(overlay, theme.surface_hud)
	crosshair := bounds_of(overlay, theme.crosshair)
	testing.expect(t, hint.width > 0, "the hint box is missing")
	testing.expect(t, crosshair.width > 0, "the crosshair is missing")

	overlaps :=
		hint.x < crosshair.x + crosshair.width &&
		crosshair.x < hint.x + hint.width &&
		hint.y < crosshair.y + crosshair.height &&
		crosshair.y < hint.y + hint.height
	testing.expectf(t, !overlaps, "the hint %v overlaps the crosshair %v", hint, crosshair)
}

@(test)
every_menu_item_selects_a_selectable_row :: proc(t: ^testing.T) {
	sim, _, hud, _ := create_state(t)
	defer game.simulation_destroy(&sim)
	hud.menu.displays = display.fallback_list()
	game.menu_open(&hud.menu)

	for item in game.Menu_Item {
		hud.menu.selected = item
		game.menu_view(&hud.menu, sim.settings, false)
		row := hud.menu.view.rows[hud.menu.view.selected]
		selectable := row.kind == .Setting || row.kind == .Action
		testing.expectf(t, selectable, "%v selected a %v row", item, row.kind)
		testing.expect_value(t, row.label, game.MENU_ITEM_NAMES[item])
	}
}

@(private)
build_atlas :: proc(t: ^testing.T, theme: renderer.UI_Theme) -> (renderer.Text_Atlas, bool) {
	set := renderer.text_theme_layer_set(theme)
	return renderer.text_atlas_build(context.allocator, &set)
}

Rect :: struct {
	x, y, width, height: f32,
}

@(private)
measure_status_panel :: proc(
	t: ^testing.T,
	sim: ^game.Simulation,
	debug: ^game.Debug_Mode,
	hud: ^game.HUD_State,
	atlas: ^renderer.Text_Atlas,
	theme: renderer.UI_Theme,
	position: [3]f32,
) -> renderer.Rows_Layout {
	snapshot := game.simulation_snapshot(sim)
	snapshot.position = position
	snapshot.velocity = {}
	snapshot.stance = .Standing
	snapshot.gait = .Walk
	snapshot.movement_state = .None
	snapshot.grounded = true

	game.hud_state_update(hud, sim, debug, snapshot, true)
	testing.expect(t, len(hud.view.rows) == game.HUD_ROW_COUNT, "the status rows went missing")
	return renderer.rows_measure(atlas, theme, hud.view.rows, {value_align = .Left})
}

@(private)
build_menu_overlay :: proc(t: ^testing.T, menu: ui.Menu) -> (overlay: renderer.Overlay, ok: bool) {
	overlay.theme = renderer.ui_theme_init(720)
	atlas, built := build_atlas(t, overlay.theme)
	testing.expect(t, built, "the atlas did not build")
	if !built {
		return {}, false
	}
	overlay.atlas = atlas
	overlay.hud_vertices = make([]renderer.HUD_Vertex, 24576, context.allocator)
	renderer.build_menu(&overlay, 1280, 720, menu)
	return overlay, true
}

@(private)
destroy_overlay_scratch :: proc(overlay: ^renderer.Overlay) {
	delete(overlay.hud_vertices, context.allocator)
	renderer.text_atlas_destroy(&overlay.atlas, context.allocator)
}

// Fills buffer with every quad drawn in one colour and returns the count. The
// tests read geometry, not pixels, so this is the only way to see the layout.
@(private)
quads_with :: proc(overlay: renderer.Overlay, color: [4]f32, buffer: []Rect) -> int {
	count := 0
	for vertex in 0 ..< overlay.hud_count / 6 {
		if count >= len(buffer) {
			break
		}
		first := overlay.hud_vertices[vertex * 6]
		if first.color != color {
			continue
		}
		quad := rect_at(overlay, vertex * 6)
		if quad.width > 0 && quad.height > 0 {
			buffer[count] = quad
			count += 1
		}
	}
	return count
}

@(private)
widest_quad :: proc(overlay: renderer.Overlay, color: [4]f32) -> Rect {
	buffer: [64]Rect
	count := quads_with(overlay, color, buffer[:])
	best: Rect
	for quad in buffer[:count] {
		if quad.width * quad.height > best.width * best.height {
			best = quad
		}
	}
	return best
}

@(private)
bounds_of :: proc(overlay: renderer.Overlay, color: [4]f32) -> Rect {
	buffer: [64]Rect
	count := quads_with(overlay, color, buffer[:])
	if count == 0 {
		return {}
	}
	bounds := buffer[0]
	for quad in buffer[1:count] {
		right := max(bounds.x + bounds.width, quad.x + quad.width)
		bottom := max(bounds.y + bounds.height, quad.y + quad.height)
		bounds.x = min(bounds.x, quad.x)
		bounds.y = min(bounds.y, quad.y)
		bounds.width = right - bounds.x
		bounds.height = bottom - bounds.y
	}
	return bounds
}

@(private)
rect_at :: proc(overlay: renderer.Overlay, first: int) -> Rect {
	x0 := overlay.hud_vertices[first].position.x
	y0 := overlay.hud_vertices[first].position.y
	x1 := x0
	y1 := y0
	for offset in 1 ..< 6 {
		position := overlay.hud_vertices[first + offset].position
		x0 = min(x0, position.x)
		y0 = min(y0, position.y)
		x1 = max(x1, position.x)
		y1 = max(y1, position.y)
	}
	return {x = x0, y = y0, width = x1 - x0, height = y1 - y0}
}
