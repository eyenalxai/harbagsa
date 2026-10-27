#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package docs_test

import "core:math"
import "core:strconv"
import "core:strings"
import "core:testing"

import "src:renderer"

COLOUR_ROWS :: 11
CONTRAST_ROWS :: 4
CONTRAST_TOLERANCE :: f32(0.05)

@(test)
colour_tokens_match_theme :: proc(t: ^testing.T) {
	doc, ok := doc_open(t, "docs/ui/colour.md")
	if !ok {
		return
	}
	defer doc_close(&doc)

	theme := renderer.ui_theme_init(720)
	checked := 0
	for line, index in doc.lines {
		cells, count := split_table_row(line)
		if count < 3 {
			continue
		}
		hex, hex_ok := parse_palette_hex(t, doc.path, index + 1, cells[1])
		if !hex_ok {
			continue
		}
		token := strip_ticks(cells[0])
		alpha, alpha_ok := strconv.parse_f32(cells[2])
		if !alpha_ok {
			testing.expectf(t, false, "%s:%d has an unreadable alpha %q", doc.path, index + 1, cells[2])
			continue
		}
		checked += 1
		check_colour_row(t, doc.path, index + 1, token, hex, alpha, theme)
	}
	testing.expectf(t, checked == COLOUR_ROWS, "%s has %d token rows, expected %d", doc.path, checked, COLOUR_ROWS)
}

@(test)
colour_contrast_table_matches_theme :: proc(t: ^testing.T) {
	doc, ok := doc_open(t, "docs/ui/colour.md")
	if !ok {
		return
	}
	defer doc_close(&doc)

	theme := renderer.ui_theme_init(720)
	surfaces := [3][4]f32{theme.surface_menu, theme.surface_raised, theme.surface_hud}
	surface_names := [3]string{"surface_menu", "surface_raised", "surface_hud"}
	checked := 0
	for line, index in doc.lines {
		cells, count := split_table_row(line)
		if count < 4 {
			continue
		}
		token := strip_ticks(cells[0])
		foreground, known := colour_token(token, theme)
		if !known {
			continue
		}
		if _, ratio_ok := parse_ratio(cells[1]); !ratio_ok {
			continue
		}
		checked += 1
		for column in 0 ..< len(surfaces) {
			ratio, read_ok := parse_ratio(cells[column + 1])
			if !read_ok {
				testing.expectf(
					t,
					false,
					"%s:%d has an unreadable contrast for %s on %s",
					doc.path,
					index + 1,
					token,
					surface_names[column],
				)
				continue
			}
			expected := renderer.ui_contrast(foreground.value, surfaces[column])
			testing.expectf(
				t,
				math.abs(ratio - expected) <= CONTRAST_TOLERANCE,
				"%s:%d says %s on %s is %v:1, theme says %v:1",
				doc.path,
				index + 1,
				token,
				surface_names[column],
				ratio,
				expected,
			)
		}
	}
	testing.expectf(
		t,
		checked == CONTRAST_ROWS,
		"%s has %d contrast rows, expected %d",
		doc.path,
		checked,
		CONTRAST_ROWS,
	)
}

check_colour_row :: proc(
	t: ^testing.T,
	doc_path: string,
	line: int,
	token: string,
	hex: u32,
	alpha: f32,
	theme: renderer.UI_Theme,
) {
	spec, known := colour_token(token, theme)
	if !known {
		testing.expectf(t, false, "%s:%d has an unknown colour token %q", doc_path, line, token)
		return
	}
	testing.expectf(
		t,
		hex == spec.hex,
		"%s:%d says %s is #%06X, %s says #%06X",
		doc_path,
		line,
		token,
		hex,
		spec.hex_name,
		spec.hex,
	)
	testing.expectf(
		t,
		approx_equal(alpha, spec.value.a),
		"%s:%d says %s alpha is %v, theme.%s.a says %v",
		doc_path,
		line,
		token,
		alpha,
		spec.field_name,
		spec.value.a,
	)
}

Colour_Token :: struct {
	hex:        u32,
	value:      [4]f32,
	hex_name:   string,
	field_name: string,
}

colour_token :: proc(token: string, theme: renderer.UI_Theme) -> (spec: Colour_Token, ok: bool) {
	switch token {
	case "text_primary":
		return {renderer.UI_COLOR_TEXT_PRIMARY, theme.text_primary, "UI_COLOR_TEXT_PRIMARY", "text_primary"},
			true
	case "text_secondary":
		return {
				renderer.UI_COLOR_TEXT_SECONDARY,
				theme.text_secondary,
				"UI_COLOR_TEXT_SECONDARY",
				"text_secondary",
			},
			true
	case "text_tertiary":
		return {
				renderer.UI_COLOR_TEXT_TERTIARY,
				theme.text_tertiary,
				"UI_COLOR_TEXT_TERTIARY",
				"text_tertiary",
			},
			true
	case "accent":
		return {renderer.UI_COLOR_ACCENT, theme.accent, "UI_COLOR_ACCENT", "accent"}, true
	case "surface_hud":
		return {renderer.UI_COLOR_SURFACE_HUD, theme.surface_hud, "UI_COLOR_SURFACE_HUD", "surface_hud"},
			true
	case "surface_menu":
		return {
				renderer.UI_COLOR_SURFACE_MENU,
				theme.surface_menu,
				"UI_COLOR_SURFACE_MENU",
				"surface_menu",
			},
			true
	case "surface_raised":
		return {
				renderer.UI_COLOR_SURFACE_RAISED,
				theme.surface_raised,
				"UI_COLOR_SURFACE_RAISED",
				"surface_raised",
			},
			true
	case "line_hairline":
		return {renderer.UI_COLOR_HAIRLINE, theme.line_hairline, "UI_COLOR_HAIRLINE", "line_hairline"},
			true
	case "line_separator":
		return {renderer.UI_COLOR_SEPARATOR, theme.line_separator, "UI_COLOR_SEPARATOR", "line_separator"},
			true
	case "slider_track":
		return {
				renderer.UI_COLOR_SLIDER_TRACK,
				theme.slider_track,
				"UI_COLOR_SLIDER_TRACK",
				"slider_track",
			},
			true
	case "scrim":
		return {renderer.UI_COLOR_SCRIM, theme.scrim, "UI_COLOR_SCRIM", "scrim"}, true
	}
	return {}, false
}

// The contrast table writes each ratio as "15.4:1".
parse_ratio :: proc(cell: string) -> (ratio: f32, ok: bool) {
	if !strings.has_suffix(cell, ":1") {
		return 0, false
	}
	return strconv.parse_f32(cell[:len(cell) - 2])
}
