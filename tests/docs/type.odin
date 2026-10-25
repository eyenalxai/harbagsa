#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package docs_test

import "core:strconv"
import "core:strings"
import "core:testing"

import "src:renderer"

TYPE_ROWS :: 5

WEIGHT_WORDINGS := [?]string{"base", "base + 100"}

@(test)
type_tokens_match_theme :: proc(t: ^testing.T) {
	doc, ok := doc_open(t, "docs/ui/type.md")
	if !ok {
		return
	}
	defer doc_close(&doc)

	theme := renderer.ui_theme_init(720)
	checked := 0
	for line, index in doc.lines {
		cells, count := split_table_row(line)
		if count < 6 {
			continue
		}
		token := strip_ticks(cells[1])
		if !strings.has_prefix(token, "type_") {
			continue
		}

		size, size_ok := strconv.parse_f32(cells[2])
		leading, leading_ok := strconv.parse_f32(cells[3])
		tracking_text := cells[5]
		if strings.has_suffix(tracking_text, " em") {
			tracking_text = tracking_text[:len(tracking_text) - 3]
		}
		tracking, tracking_ok := strconv.parse_f32(tracking_text)
		if !size_ok || !leading_ok || !tracking_ok {
			testing.expectf(t, false, "%s:%d has an unreadable number", doc.path, index + 1)
			continue
		}
		checked += 1
		check_type_row(t, doc.path, index + 1, token, size, leading, tracking, cells[4], theme)
	}
	testing.expectf(t, checked == TYPE_ROWS, "%s has %d token rows, expected %d", doc.path, checked, TYPE_ROWS)
}

check_type_row :: proc(
	t: ^testing.T,
	doc_path: string,
	line: int,
	token: string,
	size, leading, tracking: f32,
	weight: string,
	theme: renderer.UI_Theme,
) {
	expected_size: f32
	expected_leading: f32
	expected_tracking: f32
	expected_weight: f32
	size_name: string
	leading_name: string
	tracking_name: string
	field_name: string
	actual: renderer.Text_Type
	switch token {
	case "type_title":
		expected_size = renderer.UI_TEXT_SIZE_TITLE
		expected_leading = renderer.UI_LEADING_TITLE
		expected_tracking = renderer.UI_TRACKING_TITLE
		expected_weight = 500
		size_name, leading_name, tracking_name = "UI_TEXT_SIZE_TITLE", "UI_LEADING_TITLE", "UI_TRACKING_TITLE"
		field_name, actual = "type_title", theme.type_title
	case "type_body":
		expected_size = renderer.UI_TEXT_SIZE_BODY
		expected_leading = renderer.UI_LEADING_BODY
		expected_tracking = 0
		expected_weight = 400
		size_name, leading_name, tracking_name = "UI_TEXT_SIZE_BODY", "UI_LEADING_BODY", "0"
		field_name, actual = "type_body", theme.type_body
	case "type_body_strong":
		expected_size = renderer.UI_TEXT_SIZE_BODY
		expected_leading = renderer.UI_LEADING_BODY
		expected_tracking = 0
		expected_weight = 500
		size_name, leading_name, tracking_name = "UI_TEXT_SIZE_BODY", "UI_LEADING_BODY", "0"
		field_name, actual = "type_body_strong", theme.type_body_strong
	case "type_caption":
		expected_size = renderer.UI_TEXT_SIZE_CAPTION
		expected_leading = renderer.UI_LEADING_CAPTION
		expected_tracking = 0
		expected_weight = 400
		size_name, leading_name, tracking_name = "UI_TEXT_SIZE_CAPTION", "UI_LEADING_CAPTION", "0"
		field_name, actual = "type_caption", theme.type_caption
	case "type_caption_caps":
		expected_size = renderer.UI_TEXT_SIZE_CAPTION
		expected_leading = renderer.UI_LEADING_CAPTION
		expected_tracking = renderer.UI_TRACKING_CAPS
		expected_weight = 500
		size_name, leading_name, tracking_name = "UI_TEXT_SIZE_CAPTION", "UI_LEADING_CAPTION", "UI_TRACKING_CAPS"
		field_name, actual = "type_caption_caps", theme.type_caption_caps
	case:
		testing.expectf(t, false, "%s:%d has an unknown type token %q", doc_path, line, token)
		return
	}

	testing.expectf(
		t,
		approx_equal(size, expected_size),
		"%s:%d says %s size is %v, %s says %v",
		doc_path,
		line,
		token,
		size,
		size_name,
		expected_size,
	)
	testing.expectf(
		t,
		approx_equal(leading, expected_leading),
		"%s:%d says %s leading is %v, %s says %v",
		doc_path,
		line,
		token,
		leading,
		leading_name,
		expected_leading,
	)
	testing.expectf(
		t,
		approx_equal(tracking, expected_tracking),
		"%s:%d says %s tracking is %v, %s says %v",
		doc_path,
		line,
		token,
		tracking,
		tracking_name,
		expected_tracking,
	)

	// The theme stores the weight as a f32, so the table words it relative to the
	// base. Only the allowed wordings are checked here.
	weight_ok := false
	for wording in WEIGHT_WORDINGS {
		if weight == wording {
			weight_ok = true
			break
		}
	}
	testing.expectf(
		t,
		weight_ok,
		"%s:%d says %s weight is %q, want \"base\" or \"base + 100\"",
		doc_path,
		line,
		token,
		weight,
	)
	wording_weight, wording_ok := weight_from_wording(weight, theme.type_body.weight)
	testing.expectf(
		t,
		wording_ok,
		"%s:%d says %s weight is %q, which is not a weight wording",
		doc_path,
		line,
		token,
		weight,
	)
	testing.expectf(
		t,
		approx_equal(actual.weight, wording_weight),
		"%s:%d says %s weight is %q, which is %v, theme.%s.weight is %v",
		doc_path,
		line,
		token,
		weight,
		wording_weight,
		field_name,
		actual.weight,
	)
	testing.expectf(
		t,
		approx_equal(actual.weight, expected_weight),
		"%s:%d says %s weight is %q, theme.%s.weight is %v, want %v",
		doc_path,
		line,
		token,
		weight,
		field_name,
		actual.weight,
		expected_weight,
	)

	// The table has no caps column. The token name states the intent and the
	// theme struct holds the flag, so the two must agree.
	caps := strings.has_suffix(token, "_caps")
	testing.expectf(
		t,
		actual.caps == caps,
		"%s:%d names %s, so caps is %v, theme.%s.caps says %v",
		doc_path,
		line,
		token,
		caps,
		field_name,
		actual.caps,
	)
}

weight_from_wording :: proc(wording: string, base: f32) -> (weight: f32, ok: bool) {
	switch wording {
	case "base":
		return base, true
	case "base + 100":
		return min(base + 100, renderer.MAX_WEIGHT), true
	}
	return 0, false
}
