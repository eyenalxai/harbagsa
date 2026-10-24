#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package renderer_test

import "core:math"
import "core:testing"

import "src:renderer"

build_test_atlas :: proc(t: ^testing.T) -> (renderer.Text_Atlas, bool) {
	return build_weight_atlas(t, 400)
}

build_weight_atlas :: proc(t: ^testing.T, weight: f32) -> (renderer.Text_Atlas, bool) {
	theme := renderer.ui_theme_init(720, weight)
	set := renderer.text_theme_layer_set(theme)
	atlas, ok := renderer.text_atlas_build(context.allocator, &set)
	testing.expect(t, ok, "the atlas did not build")
	return atlas, ok
}

@(test)
text_atlas_covers_every_glyph_in_each_layer :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas)

	for layer in atlas.layers[:atlas.count] {
		testing.expectf(t, len(layer.glyphs) > 90, "%v has only %d glyphs", layer.key, len(layer.glyphs))
		present := 0
		for glyph in layer.glyphs {
			if glyph.present {
				present += 1
			}
		}
		testing.expectf(t, present > 90, "%v has only %d bitmaps", layer.key, present)
	}
}

@(test)
text_atlas_includes_the_separator_glyphs :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas)

	theme := renderer.ui_theme_init(720)
	layer := &atlas.layers[renderer.text_layer_index(&atlas, theme.type_body)]
	for character in ([3]rune{0x00B7, 0x00D7, 0x2026}) {
		index := glyph_for_rune(.Sans, 400, character)
		testing.expectf(t, index >= 0 && index < len(layer.glyphs), "0x%X has no glyph", character)
		if index >= 0 && index < len(layer.glyphs) {
			testing.expectf(t, layer.glyphs[index].present, "0x%X has no bitmap", character)
		}
	}
}

// HarfBuzz maps a rune the subset lacks to .notdef, and the shaper drops
// .notdef, so the text measures zero and nothing draws. The guide needs a true
// ellipsis, so the body face must carry a real glyph.
@(test)
text_atlas_measures_the_ellipsis :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas)

	theme := renderer.ui_theme_init(720)
	width := renderer.text_measure(&atlas, theme.type_body, "…")
	testing.expectf(t, width > 0, "the ellipsis measures %v", width)

	index := glyph_for_rune(.Sans, 400, 0x2026)
	testing.expectf(t, index > 0, "0x2026 maps to glyph %d, not a real glyph", index)
	layer := &atlas.layers[renderer.text_layer_index(&atlas, theme.type_body)]
	if index <= 0 || index >= len(layer.glyphs) {
		return
	}
	testing.expect(t, layer.glyphs[index].present, "the ellipsis has no bitmap")
}

@(test)
text_atlas_measures_the_mono_ellipsis :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas)

	theme := renderer.ui_theme_init(720)
	mono := theme.type_body
	mono.face = .Mono
	width := renderer.text_measure(&atlas, mono, "…")
	testing.expectf(t, width > 0, "the mono ellipsis measures %v", width)

	index := glyph_for_rune(.Mono, 400, 0x2026)
	testing.expectf(t, index > 0, "0x2026 maps to mono glyph %d, not a real glyph", index)
	layer := &atlas.layers[renderer.text_layer_index(&atlas, mono)]
	if index <= 0 || index >= len(layer.glyphs) {
		return
	}
	testing.expect(t, layer.glyphs[index].present, "the mono ellipsis has no bitmap")
}

@(test)
text_atlas_glyph_rects_stay_inside_and_do_not_overlap :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas)

	width := f32(atlas.width)
	height := f32(atlas.height)
	rects := make([dynamic][4]f32, 0, 4096, context.allocator)
	defer delete(rects)

	for layer in atlas.layers[:atlas.count] {
		for glyph, index in layer.glyphs {
			if !glyph.present {
				continue
			}
			for phase in 0 ..< renderer.TEXT_SUBPIXEL_PHASES {
				placed := glyph.phases[phase]
				u0, v0, u1, v1 := placed.uv.x, placed.uv.y, placed.uv.z, placed.uv.w
				testing.expectf(
					t,
					u0 >= 0 && v0 >= 0 && u1 <= 1 && v1 <= 1 && u0 < u1 && v0 < v1,
					"%v glyph %d phase %d has a degenerate or out of range rect",
					layer.key,
					index,
					phase,
				)
				append(&rects, [4]f32{u0 * width, v0 * height, u1 * width, v1 * height})
			}
		}
	}

	for first, index in rects[:] {
		for second in rects[index + 1:] {
			overlaps :=
				first.x < second.z &&
				second.x < first.z &&
				first.y < second.w &&
				second.y < first.w
			testing.expectf(t, !overlaps, "two glyph rects overlap: %v and %v", first, second)
		}
	}
}

@(test)
text_atlas_vertical_metrics_are_ordered :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas)

	for layer in atlas.layers[:atlas.count] {
		testing.expectf(t, layer.ascent > 0, "%v: the ascent must be positive", layer.key)
		testing.expectf(t, layer.descent < 0, "%v: the descent must be negative", layer.key)
		testing.expectf(t, layer.line_gap >= 0, "%v: the line gap must not be negative", layer.key)
	}
}

@(test)
text_atlas_advance_is_proportional_to_the_size :: proc(t: ^testing.T) {
	set: renderer.Text_Layer_Set
	renderer.text_layer_set_add(&set, {face = .Sans, weight = 400, px = 20})
	renderer.text_layer_set_add(&set, {face = .Sans, weight = 400, px = 40})
	atlas, ok := renderer.text_atlas_build(context.allocator, &set)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas)

	small := renderer.Text_Type{size = 20, line_height = 30, face = .Sans, weight = 400}
	large := small
	large.size = 40
	large.line_height = 60

	small_width := renderer.text_measure(&atlas, small, "Standing")
	large_width := renderer.text_measure(&atlas, large, "Standing")
	testing.expect(t, small_width > 0, "the advance must be positive")
	testing.expectf(
		t,
		math.abs(large_width - small_width * 2) < 0.05,
		"doubling the size must double the width: %v against %v",
		large_width,
		small_width * 2,
	)
}

// A distance field lost the inside of a one-pixel stem. Coverage has no such
// floor, and this holds that line.
@(test)
text_atlas_keeps_thin_stems_solid :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas)

	theme := renderer.ui_theme_init(720)
	index := glyph_for_rune(.Sans, 400, 'i')
	testing.expect(t, index >= 0, "i must exist")
	layer := &atlas.layers[renderer.text_layer_index(&atlas, theme.type_body)]
	if index < 0 || index >= len(layer.glyphs) {
		return
	}
	glyph := layer.glyphs[index]
	testing.expect(t, glyph.present, "i has no bitmap")

	peak: u8
	for phase in 0 ..< renderer.TEXT_SUBPIXEL_PHASES {
		placed := glyph.phases[phase]
		x0 := int(placed.uv.x * f32(atlas.width))
		y0 := int(placed.uv.y * f32(atlas.height))
		x1 := int(placed.uv.z * f32(atlas.width))
		y1 := int(placed.uv.w * f32(atlas.height))
		for y in y0 ..< y1 {
			for x in x0 ..< x1 {
				peak = max(peak, atlas.pixels[y * int(atlas.width) + x])
			}
		}
	}
	testing.expectf(t, peak >= 230, "the stem of an i peaks at %d of 255", peak)
}

@(test)
text_layer_set_is_sorted_and_unique :: proc(t: ^testing.T) {
	set: renderer.Text_Layer_Set
	renderer.text_layer_set_add(&set, {face = .Mono, weight = 400, px = 15})
	renderer.text_layer_set_add(&set, {face = .Sans, weight = 400, px = 15})
	renderer.text_layer_set_add(&set, {face = .Sans, weight = 400, px = 15})
	renderer.text_layer_set_add(&set, {face = .Sans, weight = 400, px = 21})

	testing.expect_value(t, set.count, 3)
	for index in 1 ..< set.count {
		previous := set.keys[index - 1]
		current := set.keys[index]
		ordered :=
			previous.face < current.face ||
			(previous.face == current.face &&
				(previous.weight < current.weight ||
					(previous.weight == current.weight && previous.px < current.px)))
		testing.expectf(t, ordered, "%v must sort before %v", previous, current)
	}
}

@(test)
text_theme_uses_seven_layers :: proc(t: ^testing.T) {
	theme := renderer.ui_theme_init(720)
	set := renderer.text_theme_layer_set(theme)
	testing.expect_value(t, set.count, 7)

	body_mono, caption_mono, title := false, false, false
	for key in set.keys[:set.count] {
		if key.face == .Mono && key.weight == 400 && key.px == 15 {
			body_mono = true
		}
		if key.face == .Mono && key.weight == 400 && key.px == 14 {
			caption_mono = true
		}
		if key.face == .Sans && key.weight == 500 && key.px == 21 {
			title = true
		}
	}
	testing.expect(t, body_mono, "the body mono layer is missing")
	testing.expect(t, caption_mono, "the caption mono layer is missing")
	testing.expect(t, title, "the title layer is missing")
}

@(test)
text_theme_mono_clamps_at_seven_hundred :: proc(t: ^testing.T) {
	theme := renderer.ui_theme_init(720, 900)
	set := renderer.text_theme_layer_set(theme)
	sans_nine_hundred, mono := false, false
	for key in set.keys[:set.count] {
		if key.face == .Sans && key.weight == 900 {
			sans_nine_hundred = true
		}
		if key.face == .Mono {
			mono = true
			testing.expectf(t, key.weight == 700, "mono clamped to %d", key.weight)
		}
	}
	testing.expect(t, sans_nine_hundred, "the sans face must reach 900")
	testing.expect(t, mono, "the mono layers are missing")
}

@(test)
text_theme_strong_role_sits_one_hundred_above_the_body :: proc(t: ^testing.T) {
	theme := renderer.ui_theme_init(720, 800)
	testing.expect_value(t, theme.type_body.weight, 800)
	testing.expect_value(t, theme.type_body_strong.weight, 900)
	testing.expect_value(t, theme.type_title.weight, 900)

	theme = renderer.ui_theme_init(720, 900)
	testing.expect_value(t, theme.type_body.weight, 900)
	testing.expect_value(t, theme.type_body_strong.weight, 900)

	theme = renderer.ui_theme_init(720, 100)
	testing.expect_value(t, theme.type_body.weight, 100)
	testing.expect_value(t, theme.type_body_strong.weight, 200)
}
