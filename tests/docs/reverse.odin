#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package docs_test

import "core:reflect"
import "core:strings"
import "core:testing"

import "src:renderer"

COLOUR_DOC :: "docs/ui/colour.md"
TYPE_DOC :: "docs/ui/type.md"
SPACING_DOC :: "docs/ui/spacing.md"
SPACING_PREFIX :: "spacing."

// The row-count tests walk the docs, so a token added to ui_theme.odin passes
// while the counts stay put. These tests walk the theme instead.
@(test)
theme_colours_have_a_palette_row :: proc(t: ^testing.T) {
	for field in reflect.struct_fields_zipped(renderer.UI_Theme) {
		if field.type.id != typeid_of([4]f32) {
			continue
		}
		testing.expectf(
			t,
			doc_has_token(t, COLOUR_DOC, field.name),
			"%s has no palette row for theme.%s",
			COLOUR_DOC,
			field.name,
		)
	}
}

@(test)
theme_types_have_a_type_row :: proc(t: ^testing.T) {
	for field in reflect.struct_fields_zipped(renderer.UI_Theme) {
		if field.type.id != typeid_of(renderer.Text_Type) {
			continue
		}
		testing.expectf(
			t,
			doc_has_token(t, TYPE_DOC, field.name),
			"%s has no row for theme.%s",
			TYPE_DOC,
			field.name,
		)
	}
}

@(test)
theme_spacing_has_a_spacing_row :: proc(t: ^testing.T) {
	for field in reflect.struct_fields_zipped(renderer.UI_Spacing) {
		token := strings.concatenate({SPACING_PREFIX, field.name}, context.allocator)
		found := doc_has_token(t, SPACING_DOC, token)
		delete(token, context.allocator)
		testing.expectf(
			t,
			found,
			"%s has no row for theme.spacing.%s",
			SPACING_DOC,
			field.name,
		)
	}
}

@(test)
theme_token_counts_match_the_docs :: proc(t: ^testing.T) {
	colours, types := 0, 0
	for field in reflect.struct_fields_zipped(renderer.UI_Theme) {
		if field.type.id == typeid_of([4]f32) {
			colours += 1
		}
		if field.type.id == typeid_of(renderer.Text_Type) {
			types += 1
		}
	}
	spacing := len(reflect.struct_fields_zipped(renderer.UI_Spacing))
	testing.expectf(
		t,
		colours == COLOUR_ROWS,
		"theme has %d colour fields, %s has %d palette rows",
		colours,
		COLOUR_DOC,
		COLOUR_ROWS,
	)
	testing.expectf(
		t,
		types == TYPE_ROWS,
		"theme has %d type fields, %s has %d role rows",
		types,
		TYPE_DOC,
		TYPE_ROWS,
	)
	testing.expectf(
		t,
		spacing == SPACING_ROWS,
		"theme has %d spacing fields, %s has %d scale rows",
		spacing,
		SPACING_DOC,
		SPACING_ROWS,
	)
}

doc_has_token :: proc(t: ^testing.T, path, token: string) -> bool {
	doc, ok := doc_open(t, path)
	if !ok {
		return false
	}
	defer doc_close(&doc)
	for line in doc.lines {
		cells, count := split_table_row(line)
		for cell in cells[:count] {
			if strip_ticks(cell) == token {
				return true
			}
		}
	}
	return false
}
