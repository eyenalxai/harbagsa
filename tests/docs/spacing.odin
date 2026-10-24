#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package docs_test

import "core:strconv"
import "core:strings"
import "core:testing"

import "src:renderer"

SPACING_ROWS :: 7

@(test)
spacing_tokens_match_theme :: proc(t: ^testing.T) {
	doc, ok := doc_open(t, "docs/ui/spacing.md")
	if !ok {
		return
	}
	defer doc_close(&doc)

	theme := renderer.ui_theme_init(720)
	theme_1080 := renderer.ui_theme_init(1080)
	checked := 0
	for line, index in doc.lines {
		cells, count := split_table_row(line)
		if count < 3 {
			continue
		}
		token := strip_ticks(cells[0])
		if !strings.has_prefix(token, "spacing.") {
			continue
		}
		value, value_ok := strconv.parse_f32(cells[1])
		if !value_ok {
			testing.expectf(t, false, "%s:%d has an unreadable 720p value %q", doc.path, index + 1, cells[1])
			continue
		}
		expected, known := spacing_value(theme, token)
		if !known {
			testing.expectf(t, false, "%s:%d has an unknown spacing token %q", doc.path, index + 1, token)
			continue
		}
		value_1080, value_1080_ok := strconv.parse_f32(cells[2])
		if !value_1080_ok {
			testing.expectf(t, false, "%s:%d has an unreadable 1080p value %q", doc.path, index + 1, cells[2])
			continue
		}
		expected_1080, _ := spacing_value(theme_1080, token)
		checked += 1
		testing.expectf(
			t,
			approx_equal(value, expected),
			"%s:%d says %s is %v at 720p, ui_theme_init(720).spacing says %v",
			doc.path,
			index + 1,
			token,
			value,
			expected,
		)
		testing.expectf(
			t,
			approx_equal(value_1080, expected_1080),
			"%s:%d says %s is %v at 1080p, ui_theme_init(1080).spacing says %v",
			doc.path,
			index + 1,
			token,
			value_1080,
			expected_1080,
		)
	}
	testing.expectf(t, checked == SPACING_ROWS, "%s has %d token rows, expected %d", doc.path, checked, SPACING_ROWS)
}

spacing_value :: proc(theme: renderer.UI_Theme, token: string) -> (value: f32, ok: bool) {
	switch token {
	case "spacing.xxs":
		return theme.spacing.xxs, true
	case "spacing.xs":
		return theme.spacing.xs, true
	case "spacing.sm":
		return theme.spacing.sm, true
	case "spacing.md":
		return theme.spacing.md, true
	case "spacing.lg":
		return theme.spacing.lg, true
	case "spacing.xl":
		return theme.spacing.xl, true
	case "spacing.xxl":
		return theme.spacing.xxl, true
	}
	return 0, false
}
