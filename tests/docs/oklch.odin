#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package docs_test

import "core:math"
import "core:strconv"
import "core:strings"
import "core:testing"

import "src:renderer"

OKLCH_L_TOLERANCE :: f32(0.002)
OKLCH_C_TOLERANCE :: f32(0.002)
OKLCH_H_TOLERANCE :: f32(0.5)
NEUTRAL_HUE_LIMIT :: f32(10.0)

NEUTRAL_TOKENS :: [?]string {
	"text_primary",
	"text_secondary",
	"text_tertiary",
	"surface_hud",
	"surface_menu",
	"surface_raised",
}

@(test)
palette_oklch_matches_the_hex :: proc(t: ^testing.T) {
	doc, ok := doc_open(t, "docs/ui/colour.md")
	if !ok {
		return
	}
	defer doc_close(&doc)

	checked := 0
	for line, index in doc.lines {
		cells, count := split_table_row(line)
		if count < 7 {
			continue
		}
		hex_text := strip_ticks(cells[1])
		if !strings.has_prefix(hex_text, "#") {
			continue
		}
		hex, hex_ok := strconv.parse_u64(hex_text[1:], 16)
		if !hex_ok {
			testing.expectf(t, false, "%s:%d has an unreadable hex %q", doc.path, index + 1, hex_text)
			continue
		}
		expected_l, expected_c, expected_h := oklch_from_hex(u32(hex))
		actual_l, l_ok := strconv.parse_f32(cells[3])
		actual_c, c_ok := strconv.parse_f32(cells[4])
		actual_h, h_ok := strconv.parse_f32(cells[5])
		if !l_ok || !c_ok || !h_ok {
			testing.expectf(t, false, "%s:%d has an unreadable L, C, or H", doc.path, index + 1)
			continue
		}
		checked += 1
		testing.expectf(
			t,
			abs(actual_l - expected_l) <= OKLCH_L_TOLERANCE,
			"%s:%d says L is %v, %s is %v",
			doc.path,
			index + 1,
			actual_l,
			hex_text,
			expected_l,
		)
		testing.expectf(
			t,
			abs(actual_c - expected_c) <= OKLCH_C_TOLERANCE,
			"%s:%d says C is %v, %s is %v",
			doc.path,
			index + 1,
			actual_c,
			hex_text,
			expected_c,
		)
		// Hue is undefined when chroma is zero, so a white or black row has no
		// hue to check.
		if expected_c >= 0.001 {
			testing.expectf(
				t,
				abs(actual_h - expected_h) <= OKLCH_H_TOLERANCE,
				"%s:%d says H is %v, %s is %v",
				doc.path,
				index + 1,
				actual_h,
				hex_text,
				expected_h,
			)
		}
	}
	testing.expectf(t, checked == COLOUR_ROWS, "%s has %d OKLCH rows, expected %d", doc.path, checked, COLOUR_ROWS)
}

@(test)
neutral_hues_share_one_hue :: proc(t: ^testing.T) {
	doc, ok := doc_open(t, "docs/ui/colour.md")
	if !ok {
		return
	}
	defer doc_close(&doc)

	lowest := f32(360)
	highest := f32(0)
	checked := 0
	for line, index in doc.lines {
		cells, count := split_table_row(line)
		if count < 7 {
			continue
		}
		token := strip_ticks(cells[0])
		if !neutral_token(token) {
			continue
		}
		hex_text := strip_ticks(cells[1])
		hex, hex_ok := strconv.parse_u64(hex_text[1:], 16)
		if !hex_ok {
			testing.expectf(t, false, "%s:%d has an unreadable hex %q", doc.path, index + 1, hex_text)
			continue
		}
		_, _, hue := oklch_from_hex(u32(hex))
		checked += 1
		lowest = min(lowest, hue)
		highest = max(highest, hue)
	}
	testing.expectf(t, checked == len(NEUTRAL_TOKENS), "%s has %d neutral rows, expected %d", doc.path, checked, len(NEUTRAL_TOKENS))
	testing.expectf(
		t,
		highest - lowest <= NEUTRAL_HUE_LIMIT,
		"%s neutral hues span %v degrees, want at most %v",
		doc.path,
		highest - lowest,
		NEUTRAL_HUE_LIMIT,
	)
}

@(private)
neutral_token :: proc(token: string) -> bool {
	for neutral in NEUTRAL_TOKENS {
		if token == neutral {
			return true
		}
	}
	return false
}

// The conversion follows the OKLab matrices. `srgb_to_linear` is the same
// function the theme uses, so the test and the renderer share one sRGB decode.
@(private)
oklch_from_hex :: proc(hex: u32) -> (lightness, chroma, hue: f32) {
	r := renderer.srgb_to_linear(u8(hex >> 16))
	g := renderer.srgb_to_linear(u8(hex >> 8))
	b := renderer.srgb_to_linear(u8(hex))

	l := 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
	m := 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
	s := 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
	l_ := math.cbrt(l)
	m_ := math.cbrt(m)
	s_ := math.cbrt(s)

	lightness = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
	a := 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
	bb := 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
	chroma = math.sqrt(a * a + bb * bb)
	hue = math.atan2(bb, a) * 180.0 / math.PI
	if hue < 0 {
		hue += 360
	}
	return
}
