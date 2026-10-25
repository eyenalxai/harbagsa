#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

// A sweep reads one scenario once and parses it per combination, so stdin and a
// large `extends` chain are not read again for every value.
Scenario_File :: struct {
	path:     string,
	data:     string,
	base_dir: string,
}

scenario_file_read :: proc(path: string, allocator: mem.Allocator) -> (Scenario_File, string) {
	file := Scenario_File{path = strings.clone(path, allocator)}
	if path == "-" {
		data, stdin_error := read_stdin(allocator)
		if stdin_error != "" {
			scenario_file_destroy(&file, allocator)
			return {}, stdin_error
		}
		file.data = string(data)
		return file, ""
	}
	data, read_error := os.read_entire_file(path, allocator)
	if read_error != nil {
		scenario_file_destroy(&file, allocator)
		return {}, fmt.aprintf("cannot read %s: %v", path, read_error, allocator = allocator)
	}
	file.data = string(data)
	file.base_dir = strings.clone(scenario_base_dir(path), allocator)
	return file, ""
}

scenario_file_destroy :: proc(file: ^Scenario_File, allocator: mem.Allocator) {
	if file.data != "" {
		delete(file.data, allocator)
	}
	if file.path != "" {
		delete(file.path, allocator)
	}
	if file.base_dir != "" {
		delete(file.base_dir, allocator)
	}
	file^ = {}
}

scenario_file_parse :: proc(
	file: ^Scenario_File,
	overrides: []Parameter_Override,
	allocator: mem.Allocator,
) -> (Scenario, string) {
	scenario, parse_error := scenario_parse_with_base(
		file.data,
		file.base_dir,
		overrides,
		allocator,
	)
	if parse_error != "" {
		return {}, parse_error
	}
	scenario.source.path = strings.clone(file.path, allocator)
	return scenario, ""
}

scenario_load :: proc(
	path: string,
	allocator: mem.Allocator,
	overrides: []Parameter_Override = nil,
) -> (Scenario, string) {
	file, read_error := scenario_file_read(path, allocator)
	if read_error != "" {
		return {}, read_error
	}
	defer scenario_file_destroy(&file, allocator)
	return scenario_file_parse(&file, overrides, allocator)
}

@(private)
read_stdin :: proc(allocator: mem.Allocator) -> ([]u8, string) {
	buffer := make([dynamic]u8, 0, 4096, allocator)
	chunk: [4096]u8
	for {
		count, read_error := os.read(os.stdin, chunk[:])
		if count > 0 {
			append(&buffer, ..chunk[:count])
		}
		if read_error != nil || count == 0 {
			break
		}
	}
	if len(buffer) == 0 {
		delete(buffer)
		return nil, format_error("%s", "scenario stdin is empty")
	}
	return buffer[:], ""
}
