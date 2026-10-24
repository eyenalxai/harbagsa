#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package renderer_test

import "core:math"
import "core:testing"

import "src:renderer"

@(test)
text_measure_of_empty_text_is_zero :: proc(t: ^testing.T) {
	atlas, ok := renderer.text_atlas_build(context.allocator)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

	theme := renderer.ui_theme_init(720)
	testing.expect_value(t, renderer.text_measure(&atlas, theme.type_body, ""), 0)
}

@(test)
text_measure_of_one_glyph_is_its_advance :: proc(t: ^testing.T) {
	atlas, ok := renderer.text_atlas_build(context.allocator)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

	theme := renderer.ui_theme_init(720)
	index, found := renderer.text_codepoint_index('M')
	testing.expect(t, found, "M must exist")

	scale := theme.type_body.size / atlas.base_px
	expected := atlas.glyphs[int(renderer.Text_Weight.Regular)][index].advance * scale
	testing.expectf(
		t,
		math.abs(renderer.text_measure(&atlas, theme.type_body, "M") - expected) < 0.01,
		"one glyph must measure its own advance",
	)
}

@(test)
text_tracking_adds_a_gap_between_glyphs_only :: proc(t: ^testing.T) {
	atlas, ok := renderer.text_atlas_build(context.allocator)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

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
	atlas, ok := renderer.text_atlas_build(context.allocator)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

	theme := renderer.ui_theme_init(720)
	style := theme.type_body
	scale := style.size / atlas.base_px
	a, a_ok := renderer.text_codepoint_index('A')
	v, v_ok := renderer.text_codepoint_index('V')
	testing.expect(t, a_ok && v_ok, "A and V must exist")

	glyphs := atlas.glyphs[int(renderer.Text_Weight.Regular)]
	advances := (glyphs[a].advance + glyphs[v].advance) * scale
	measured := renderer.text_measure(&atlas, style, "AV")
	testing.expectf(
		t,
		measured < advances - 0.01,
		"AV must kern tighter: %v measured against %v",
		measured,
		advances,
	)
}

@(test)
text_measure_skips_glyphs_outside_the_atlas :: proc(t: ^testing.T) {
	atlas, ok := renderer.text_atlas_build(context.allocator)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

	theme := renderer.ui_theme_init(720)
	measured := renderer.text_measure(&atlas, theme.type_body, "\u2603")
	testing.expectf(t, measured == 0, "an unsupported glyph must not measure, got %v", measured)
}

@(test)
text_baseline_sits_inside_the_line_box :: proc(t: ^testing.T) {
	atlas, ok := renderer.text_atlas_build(context.allocator)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

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
}
