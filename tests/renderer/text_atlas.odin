#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package renderer_test

import "core:math"
import "core:testing"

import "src:renderer"

build_test_atlas :: proc(t: ^testing.T) -> (renderer.Text_Atlas, bool) {
	theme := renderer.ui_theme_init(720)
	set := renderer.text_theme_layer_set(theme)
	atlas, ok := renderer.text_atlas_build(context.allocator, &set)
	testing.expect(t, ok, "the atlas did not build")
	return atlas, ok
}

@(test)
text_atlas_covers_ascii_for_every_layer :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

	for layer in atlas.layers[:atlas.count] {
		for codepoint in rune(0x20) ..= rune(0x7E) {
			index, found := renderer.text_codepoint_index(codepoint)
			testing.expectf(t, found, "%v: 0x%X has no index", layer.key, codepoint)
			glyph := layer.glyphs[index]
			testing.expectf(t, glyph.advance > 0, "%v: 0x%X has no advance", layer.key, codepoint)
			if codepoint != ' ' {
				testing.expectf(t, glyph.present, "%v: 0x%X has no bitmap", layer.key, codepoint)
			}
		}
	}
}

@(test)
text_atlas_includes_the_separator_glyphs :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

	extras := [2]rune{0x00B7, 0x00D7}
	for codepoint in extras {
		index, found := renderer.text_codepoint_index(codepoint)
		testing.expectf(t, found, "0x%X has no index", codepoint)
		testing.expectf(
			t,
			atlas.layers[0].glyphs[index].present,
			"0x%X has no bitmap",
			codepoint,
		)
	}
}

@(test)
text_atlas_glyph_rects_stay_inside_and_do_not_overlap :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

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
			testing.expectf(
				t,
				!overlaps,
				"two glyph rects overlap: %v and %v",
				first,
				second,
			)
		}
	}
}

@(test)
text_atlas_vertical_metrics_are_ordered :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

	for layer in atlas.layers[:atlas.count] {
		testing.expectf(t, layer.ascent > 0, "%v: the ascent must be positive", layer.key)
		testing.expectf(t, layer.descent < 0, "%v: the descent must be negative", layer.key)
		testing.expectf(t, layer.line_gap >= 0, "%v: the line gap must not be negative", layer.key)
	}
}

@(test)
text_atlas_keeps_the_kerning_pairs :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

	a, a_ok := renderer.text_codepoint_index('A')
	v, v_ok := renderer.text_codepoint_index('V')
	testing.expect(t, a_ok && v_ok, "A and V must exist")

	// The subset keeps the legacy kern table; losing it during a re-subset would
	// silently widen every tight pair.
	testing.expectf(
		t,
		atlas.layers[0].kern[a * renderer.TEXT_CODEPOINT_COUNT + v] < 0,
		"A/V must kern tighter than the sum of its advances",
	)
}

@(test)
text_atlas_advance_is_proportional_to_the_size :: proc(t: ^testing.T) {
	set: renderer.Text_Layer_Set
	renderer.text_layer_set_add(&set, {weight = .Regular, px = 20})
	renderer.text_layer_set_add(&set, {weight = .Regular, px = 40})
	atlas, ok := renderer.text_atlas_build(context.allocator, &set)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

	small := renderer.ui_theme_init(720).type_body
	small.size = 20
	large := small
	large.size = 40

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

// A distance field lost the inside of a one-pixel stem: the sampled distance at
// the stem centre never left the antialiasing ramp, so the stem drew grey and
// broken. Coverage has no such floor, and this holds that line.
@(test)
text_atlas_keeps_thin_stems_solid :: proc(t: ^testing.T) {
	atlas, ok := build_test_atlas(t)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

	theme := renderer.ui_theme_init(720)
	index, found := renderer.text_codepoint_index('i')
	testing.expect(t, found, "i must exist")
	layer := &atlas.layers[renderer.text_layer_index(&atlas, theme.type_body)]
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
	renderer.text_layer_set_add(&set, {weight = .Mono, px = 15})
	renderer.text_layer_set_add(&set, {weight = .Regular, px = 15})
	renderer.text_layer_set_add(&set, {weight = .Regular, px = 15})
	renderer.text_layer_set_add(&set, {weight = .Regular, px = 21})

	testing.expect_value(t, set.count, 3)
	for index in 1 ..< set.count {
		testing.expect(t, set.keys[index - 1].weight < set.keys[index].weight ||
			(set.keys[index - 1].weight == set.keys[index].weight &&
				set.keys[index - 1].px < set.keys[index].px))
	}
}
