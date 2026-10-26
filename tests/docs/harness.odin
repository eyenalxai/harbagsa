#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package docs_test

import "core:os"
import "core:strings"
import "core:testing"

import "src:harness"

HARNESS_PAGES := [?]string{"README.md", "docs/agents/harness.md"}

@(test)
harness_pages_name_every_command :: proc(t: ^testing.T) {
	document := harness.schema_build(context.allocator)
	defer harness.schema_destroy(&document, context.allocator)
	for page in HARNESS_PAGES {
		data, read_error := os.read_entire_file(page, context.temp_allocator)
		if read_error != nil {
			testing.expectf(t, false, "cannot read %s: %v", page, read_error)
			continue
		}
		text := string(data)
		for command in document.commands {
			testing.expectf(
				t,
				strings.contains(text, command.name),
				"%s does not name the %q command",
				page,
				command.name,
			)
		}
	}
}

@(test)
harness_pages_name_every_capture_shape :: proc(t: ^testing.T) {
	document := harness.schema_build(context.allocator)
	defer harness.schema_destroy(&document, context.allocator)
	for page in HARNESS_PAGES {
		data, read_error := os.read_entire_file(page, context.temp_allocator)
		if read_error != nil {
			testing.expectf(t, false, "cannot read %s: %v", page, read_error)
			continue
		}
		text := string(data)
		for target in document.capture_targets {
			testing.expectf(t, strings.contains(text, target), "%s does not name target %q", page, target)
		}
		for format in document.capture_formats {
			testing.expectf(t, strings.contains(text, format), "%s does not name format %q", page, format)
		}
		for operator in document.check_operators {
			testing.expectf(t, strings.contains(text, operator), "%s does not name operator %q", page, operator)
		}
	}
}
