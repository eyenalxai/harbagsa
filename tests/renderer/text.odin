#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package renderer_test

import "core:math"
import "core:testing"

import "src:renderer"

@(test)
text_measure_of_empty_text_is_zero :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas)

	theme := renderer.ui_theme_init(720)
	testing.expect_value(t, renderer.text_measure(&atlas, theme.type_body, ""), 0)
}

@(test)
text_measure_of_one_glyph_is_its_advance :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas)

	theme := renderer.ui_theme_init(720)
	one := renderer.text_measure(&atlas, theme.type_body, "M")
	two := renderer.text_measure(&atlas, theme.type_body, "MM")
	testing.expect(t, one > 0, "the glyph must advance")
	testing.expectf(
		t,
		math.abs(two - one * 2) < 0.01,
		"two glyphs must advance twice: %v against %v",
		two,
		one * 2,
	)
}

@(test)
text_tracking_adds_a_gap_between_glyphs_only :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas)

	theme := renderer.ui_theme_init(720)
	tracked := theme.type_caption_caps
	testing.expect(t, tracked.tracking > 0, "the caps style must carry tracking")

	plain := tracked
	plain.tracking = 0

	text := "AB"
	gap := tracked.tracking * tracked.size
	difference :=
		renderer.text_measure(&atlas, tracked, text) - renderer.text_measure(&atlas, plain, text)
	testing.expectf(
		t,
		math.abs(difference - gap) < 0.01,
		"one gap for two glyphs, got %v for a gap of %v",
		difference,
		gap,
	)
}

@(test)
text_kerning_tightens_a_pair :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas)

	theme := renderer.ui_theme_init(720)
	style := theme.type_body
	measured := renderer.text_measure(&atlas, style, "AV")
	separate :=
		renderer.text_measure(&atlas, style, "A") + renderer.text_measure(&atlas, style, "V")
	testing.expectf(
		t,
		measured < separate - 0.01,
		"AV must kern tighter: %v measured against %v",
		measured,
		separate,
	)
}

// Roboto Condensed widens as the axis rises. The atlas key must carry the
// weight, or the heavy atlas would silently reuse the regular advances.
@(test)
text_weight_changes_the_advance :: proc(t: ^testing.T) {
	light_atlas, light_ok := build_weight_atlas(t, 100)
	testing.expect(t, light_ok, "the light atlas did not build")
	defer renderer.text_atlas_destroy(&light_atlas)
	heavy_atlas, heavy_ok := build_weight_atlas(t, 900)
	testing.expect(t, heavy_ok, "the heavy atlas did not build")
	defer renderer.text_atlas_destroy(&heavy_atlas)

	text := "Hamburgefonstiv"
	light := renderer.text_measure(&light_atlas, renderer.ui_theme_init(720, 100).type_body, text)
	heavy := renderer.text_measure(&heavy_atlas, renderer.ui_theme_init(720, 900).type_body, text)
	testing.expectf(t, heavy > light, "900 must be wider than 100: %v against %v", heavy, light)
}

@(test)
text_measure_skips_glyphs_outside_the_atlas :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas)

	theme := renderer.ui_theme_init(720)
	measured := renderer.text_measure(&atlas, theme.type_body, "\u2603")
	testing.expectf(t, measured == 0, "an unsupported glyph must not measure, got %v", measured)
}

@(test)
text_baseline_sits_inside_the_line_box :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas)

	theme := renderer.ui_theme_init(720)
	for style in ([3]renderer.Text_Type {
		theme.type_title,
		theme.type_body,
		theme.type_caption,
	}) {
		baseline := renderer.text_baseline(&atlas, style)
		testing.expectf(
			t,
			baseline > 0 && baseline < style.line_height,
			"the baseline %v must sit inside a %v line box",
			baseline,
			style.line_height,
		)
	}
}

// The atlas samples one texel per pixel, so a glyph quad that lands on a
// fraction resamples the coverage and blurs the edge.
@(test)
text_quads_land_on_the_pixel_grid :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas)

	theme := renderer.ui_theme_init(720)
	overlay := renderer.Overlay {
		atlas = atlas,
		theme = theme,
	}
	overlay.hud_vertices = make([]renderer.HUD_Vertex, 4096, context.allocator)
	defer delete(overlay.hud_vertices, context.allocator)

	renderer.text_emit(
		&overlay,
		12.375,
		20.75,
		{type = theme.type_body, color = {1, 1, 1, 1}},
		"Window mode",
	)
	testing.expect(t, overlay.hud_count > 0, "the text did not draw")
	for vertex in overlay.hud_vertices[:overlay.hud_count] {
		testing.expectf(
			t,
			vertex.position.x == math.floor(vertex.position.x) &&
			vertex.position.y == math.floor(vertex.position.y),
			"a glyph corner sits at %v",
			vertex.position,
		)
	}
}

// The phase quantizes position to a quarter pixel. A fraction near 1 must carry
// into the origin instead of rounding to phase four and snapping back a pixel.
@(test)
text_phase_never_drifts_a_pixel :: proc(t: ^testing.T) {
	for step in 0 ..= 80 {
		position := 10.0 + f32(step) / 80.0
		origin, phase := renderer.text_place(position)
		testing.expectf(
			t,
			origin == math.floor(origin),
			"the origin %v for %v is not a whole pixel",
			origin,
			position,
		)
		testing.expectf(
			t,
			phase >= 0 && phase < renderer.TEXT_SUBPIXEL_PHASES,
			"the phase %v for %v is out of range",
			phase,
			position,
		)
		placed := origin + f32(phase) / f32(renderer.TEXT_SUBPIXEL_PHASES)
		testing.expectf(
			t,
			math.abs(placed - position) <= 0.125,
			"a glyph at %v landed at %v",
			position,
			placed,
		)
	}
}

@(test)
theme_contrast_meets_the_floor :: proc(t: ^testing.T) {
	theme := renderer.ui_theme_init(720)
	backdrop := [4]f32{0.35, 0.45, 0.55, 1.0}

	surfaces := [2][4]f32 {
		renderer.ui_composite(theme.surface_hud, backdrop),
		renderer.ui_composite(theme.surface_menu, theme.scrim),
	}
	pairs := [2][4]f32{theme.text_primary, theme.text_secondary}
	for surface in surfaces {
		for pair in pairs {
			ratio := renderer.ui_contrast(pair, surface)
			testing.expectf(t, ratio >= 4.5, "body text contrast is %v", ratio)
		}
	}

	raised := renderer.ui_composite(theme.surface_raised, surfaces[1])
	testing.expectf(
		t,
		renderer.ui_contrast(theme.text_primary, raised) >= 4.5,
		"selected row text must stay readable",
	)
	testing.expectf(
		t,
		renderer.ui_contrast(theme.accent, raised) >= 3.0,
		"the accent bar is a non-text element and needs 3:1",
	)
	track := renderer.ui_composite(theme.slider_track, raised)
	testing.expectf(
		t,
		renderer.ui_contrast(track, raised) >= 3.0,
		"the slider track is a non-text element and needs 3:1",
	)
}
