#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:strings"

// The CLI override is the same gated command, compiled from KEY=VALUE pairs.
// Reusing the JSON parser keeps one field vocabulary and one error path.
build_renderer_debug_command :: proc(
	options: Common_Options,
	allocator: mem.Allocator,
) -> (Command, string) {
	if options.debug_override_count == 0 {
		return {}, ""
	}
	builder := strings.builder_make(allocator)
	strings.write_string(&builder, "{")
	for index in 0 ..< options.debug_override_count {
		override := options.debug_overrides[index]
		if index > 0 {
			strings.write_string(&builder, ",")
		}
		fmt.sbprintf(&builder, "%q:%s", override.key, override.value)
	}
	strings.write_string(&builder, `,"cmd":"renderer_debug"}`)
	line := strings.to_string(builder)
	defer delete(line, allocator)
	command, parse_error := command_parse_string(line, allocator)
	if parse_error != "" {
		return {}, fmt.aprintf(
			"--renderer-debug: %s",
			parse_error,
			allocator = allocator,
		)
	}
	return command, ""
}

inject_command :: proc(scenario: ^Scenario, command: Command) {
	append(&scenario.commands, command)
	for index := len(scenario.commands) - 1; index > 0; index -= 1 {
		scenario.commands[index], scenario.commands[index - 1] =
			scenario.commands[index - 1], scenario.commands[index]
	}
}
