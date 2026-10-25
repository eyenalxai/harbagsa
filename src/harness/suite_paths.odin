#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:strings"

suite_resolve_path :: proc(selector: string, allocator: mem.Allocator) -> string {
	if strings.contains(selector, "/") || strings.has_suffix(selector, ".json") {
		return strings.clone(selector, allocator)
	}
	return fmt.aprintf("suites/%s.json", selector, allocator = allocator)
}

suite_scenario_path :: proc(selector: string, allocator: mem.Allocator) -> string {
	if strings.contains(selector, "/") || strings.has_suffix(selector, ".json") {
		return strings.clone(selector, allocator)
	}
	return fmt.aprintf("scenarios/%s.json", selector, allocator = allocator)
}
