#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package docs_test

import "core:strconv"
import "core:strings"
import "core:testing"

import "src:renderer"

COLOUR_ROWS :: 12

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
		hex_text := strip_ticks(cells[1])
		if !strings.has_prefix(hex_text, "#") {
			continue
		}

		token := strip_ticks(cells[0])
		hex, hex_ok := strconv.parse_u64(hex_text[1:], 16)
		if !hex_ok {
			testing.expectf(t, false, "%s:%d has an unreadable hex %q", doc.path, index + 1, hex_text)
			continue
		}
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

check_colour_row :: proc(
	t: ^testing.T,
	doc_path: string,
	line: int,
	token: string,
	hex: u64,
	alpha: f32,
	theme: renderer.UI_Theme,
) {
	expected_hex: u32
	expected_alpha: f32
	hex_name: string
	field_name: string
	switch token {
	case "text_primary":
		expected_hex = renderer.UI_COLOR_TEXT_PRIMARY
		expected_alpha = theme.text_primary.a
		hex_name, field_name = "UI_COLOR_TEXT_PRIMARY", "text_primary"
	case "text_secondary":
		expected_hex = renderer.UI_COLOR_TEXT_SECONDARY
		expected_alpha = theme.text_secondary.a
		hex_name, field_name = "UI_COLOR_TEXT_SECONDARY", "text_secondary"
	case "text_tertiary":
		expected_hex = renderer.UI_COLOR_TEXT_TERTIARY
		expected_alpha = theme.text_tertiary.a
		hex_name, field_name = "UI_COLOR_TEXT_TERTIARY", "text_tertiary"
	case "accent":
		expected_hex = renderer.UI_COLOR_ACCENT
		expected_alpha = theme.accent.a
		hex_name, field_name = "UI_COLOR_ACCENT", "accent"
	case "surface_hud":
		expected_hex = renderer.UI_COLOR_SURFACE_HUD
		expected_alpha = theme.surface_hud.a
		hex_name, field_name = "UI_COLOR_SURFACE_HUD", "surface_hud"
	case "surface_menu":
		expected_hex = renderer.UI_COLOR_SURFACE_MENU
		expected_alpha = theme.surface_menu.a
		hex_name, field_name = "UI_COLOR_SURFACE_MENU", "surface_menu"
	case "surface_raised":
		expected_hex = renderer.UI_COLOR_SURFACE_RAISED
		expected_alpha = theme.surface_raised.a
		hex_name, field_name = "UI_COLOR_SURFACE_RAISED", "surface_raised"
	case "line_hairline":
		expected_hex = renderer.UI_COLOR_HAIRLINE
		expected_alpha = theme.line_hairline.a
		hex_name, field_name = "UI_COLOR_HAIRLINE", "line_hairline"
	case "line_separator":
		expected_hex = renderer.UI_COLOR_SEPARATOR
		expected_alpha = theme.line_separator.a
		hex_name, field_name = "UI_COLOR_SEPARATOR", "line_separator"
	case "scrim":
		expected_hex = renderer.UI_COLOR_SCRIM
		expected_alpha = theme.scrim.a
		hex_name, field_name = "UI_COLOR_SCRIM", "scrim"
	case "crosshair":
		expected_hex = renderer.UI_COLOR_HAIRLINE
		expected_alpha = theme.crosshair.a
		hex_name, field_name = "UI_COLOR_HAIRLINE", "crosshair"
	case "crosshair_edge":
		expected_hex = renderer.UI_COLOR_SCRIM
		expected_alpha = theme.crosshair_edge.a
		hex_name, field_name = "UI_COLOR_SCRIM", "crosshair_edge"
	case:
		testing.expectf(t, false, "%s:%d has an unknown colour token %q", doc_path, line, token)
		return
	}

	testing.expectf(
		t,
		hex == u64(expected_hex),
		"%s:%d says %s is #%06X, %s says #%06X",
		doc_path,
		line,
		token,
		hex,
		hex_name,
		expected_hex,
	)
	testing.expectf(
		t,
		approx_equal(alpha, expected_alpha),
		"%s:%d says %s alpha is %v, theme.%s.a says %v",
		doc_path,
		line,
		token,
		alpha,
		field_name,
		expected_alpha,
	)
}
