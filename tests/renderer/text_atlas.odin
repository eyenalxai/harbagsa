#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package renderer_test

import "core:math"
import "core:testing"

import "src:renderer"

@(test)
text_atlas_covers_ascii_for_every_weight :: proc(t: ^testing.T) {
	atlas, ok := renderer.text_atlas_build(context.allocator)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

	for weight_index in 0 ..< renderer.TEXT_WEIGHT_COUNT {
		weight := renderer.Text_Weight(weight_index)
		for codepoint in rune(0x20) ..= rune(0x7E) {
			index, found := renderer.text_codepoint_index(codepoint)
			testing.expectf(t, found, "%v: 0x%X has no index", weight, codepoint)
			glyph := atlas.glyphs[weight_index][index]
			testing.expectf(t, glyph.advance > 0, "%v: 0x%X has no advance", weight, codepoint)
			if codepoint != ' ' {
				testing.expectf(t, glyph.present, "%v: 0x%X has no bitmap", weight, codepoint)
			}
		}
	}
}

@(test)
text_atlas_includes_the_separator_glyphs :: proc(t: ^testing.T) {
	atlas, ok := renderer.text_atlas_build(context.allocator)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

	extras := [2]rune{0x00B7, 0x00D7}
	for codepoint in extras {
		index, found := renderer.text_codepoint_index(codepoint)
		testing.expectf(t, found, "0x%X has no index", codepoint)
		testing.expectf(
			t,
			atlas.glyphs[int(renderer.Text_Weight.Regular)][index].present,
			"0x%X has no bitmap",
			codepoint,
		)
	}
}

@(test)
text_atlas_glyph_rects_stay_inside_and_do_not_overlap :: proc(t: ^testing.T) {
	atlas, ok := renderer.text_atlas_build(context.allocator)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

	rects: [renderer.TEXT_WEIGHT_COUNT][renderer.TEXT_CODEPOINT_COUNT][4]f32
	width := f32(atlas.width)
	height := f32(atlas.height)
	for weight_index in 0 ..< renderer.TEXT_WEIGHT_COUNT {
		weight := renderer.Text_Weight(weight_index)
		for glyph, index in atlas.glyphs[weight_index] {
			if !glyph.present {
				continue
			}
			u0, v0, u1, v1 := glyph.uv.x, glyph.uv.y, glyph.uv.z, glyph.uv.w
			testing.expectf(
				t,
				u0 >= 0 && v0 >= 0 && u1 <= 1 && v1 <= 1 && u0 < u1 && v0 < v1,
				"%v glyph %d has a degenerate or out of range rect",
				weight,
				index,
			)
			rects[weight_index][index] = {u0 * width, v0 * height, u1 * width, v1 * height}
		}
	}

	for weight_index in 0 ..< renderer.TEXT_WEIGHT_COUNT {
		weight := renderer.Text_Weight(weight_index)
		for index in 0 ..< renderer.TEXT_CODEPOINT_COUNT {
			if !atlas.glyphs[weight_index][index].present {
				continue
			}
			first := rects[weight_index][index]
			for other in index + 1 ..< renderer.TEXT_CODEPOINT_COUNT {
				if !atlas.glyphs[weight_index][other].present {
					continue
				}
				second := rects[weight_index][other]
				overlaps :=
					first.x < second.z &&
					second.x < first.z &&
					first.y < second.w &&
					second.y < first.w
				testing.expectf(
					t,
					!overlaps,
					"%v glyphs %d and %d overlap",
					weight,
					index,
					other,
				)
			}
		}
	}
}

@(test)
text_atlas_vertical_metrics_are_ordered :: proc(t: ^testing.T) {
	atlas, ok := renderer.text_atlas_build(context.allocator)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

	testing.expect(t, atlas.ascent > 0, "the ascent must be positive")
	testing.expect(t, atlas.descent < 0, "the descent must be negative")
	testing.expect(t, atlas.line_gap >= 0, "the line gap must not be negative")
	testing.expect(t, atlas.base_px > 0, "the base size must be positive")
}

@(test)
text_atlas_keeps_the_kerning_pairs :: proc(t: ^testing.T) {
	atlas, ok := renderer.text_atlas_build(context.allocator)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

	a, a_ok := renderer.text_codepoint_index('A')
	v, v_ok := renderer.text_codepoint_index('V')
	testing.expect(t, a_ok && v_ok, "A and V must exist")

	// The subset keeps the legacy kern table; losing it during a re-subset would
	// silently widen every tight pair.
	testing.expectf(
		t,
		atlas.kern[int(renderer.Text_Weight.Regular)][a * renderer.TEXT_CODEPOINT_COUNT + v] < 0,
		"A/V must kern tighter than the sum of its advances",
	)
}

@(test)
text_atlas_advance_is_proportional_to_the_size :: proc(t: ^testing.T) {
	atlas, ok := renderer.text_atlas_build(context.allocator)
	testing.expect(t, ok, "the atlas did not build")
	defer renderer.text_atlas_destroy(&atlas, context.allocator)

	index, found := renderer.text_codepoint_index('M')
	testing.expect(t, found, "M must exist")
	base := atlas.glyphs[int(renderer.Text_Weight.Regular)][index].advance
	scaled := base * (36.0 / atlas.base_px)
	testing.expect(t, base > 0, "the advance must be positive")
	testing.expectf(
		t,
		math.abs(scaled - base * 0.75) < 0.001,
		"the advance must scale linearly with the requested size",
	)
}
