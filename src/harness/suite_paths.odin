#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

// A suite names its manifests and scenarios from the repository root, not from
// whatever directory the caller happens to use. Walk up from the working
// directory, then from the binary beside bin/, so `suite renderer` works from a
// subdirectory and from a test harness.
repo_root :: proc(allocator: mem.Allocator) -> string {
	if cwd, error := os.get_working_directory(context.temp_allocator); error == nil {
		if root, found := repo_root_from(cwd, allocator); found {
			return root
		}
	}
	if executable, error := os.get_executable_directory(context.temp_allocator); error == nil {
		parent := filepath.dir(executable)
		if root, found := repo_root_from(parent, allocator); found {
			return root
		}
	}
	cwd, error := os.get_working_directory(allocator)
	if error != nil {
		return strings.clone(".", allocator)
	}
	return cwd
}

@(private)
repo_root_from :: proc(start: string, allocator: mem.Allocator) -> (string, bool) {
	walk := start
	for {
		suites := join_path({walk, "suites"}, context.temp_allocator)
		scenarios := join_path({walk, "scenarios"}, context.temp_allocator)
		if os.is_dir(suites) && os.is_dir(scenarios) {
			return strings.clone(walk, allocator), true
		}
		parent := filepath.dir(walk)
		if parent == walk || parent == "" || parent == "." {
			return "", false
		}
		walk = parent
	}
}

suite_resolve_path :: proc(selector: string, allocator: mem.Allocator) -> string {
	if strings.contains(selector, "/") || strings.has_suffix(selector, ".json") {
		if os.is_file(selector) {
			return strings.clone(selector, allocator)
		}
		root := repo_root(context.temp_allocator)
		candidate := join_path({root, selector}, allocator)
		if os.is_file(candidate) {
			return candidate
		}
		delete(candidate, allocator)
		return strings.clone(selector, allocator)
	}
	root := repo_root(context.temp_allocator)
	name := fmt.aprintf("%s.json", selector, allocator = context.temp_allocator)
	return join_path({root, "suites", name}, allocator)
}

suite_scenario_path :: proc(selector: string, allocator: mem.Allocator) -> string {
	if strings.contains(selector, "/") || strings.has_suffix(selector, ".json") {
		if os.is_file(selector) {
			return strings.clone(selector, allocator)
		}
		root := repo_root(context.temp_allocator)
		candidate := join_path({root, selector}, allocator)
		if os.is_file(candidate) {
			return candidate
		}
		delete(candidate, allocator)
		return strings.clone(selector, allocator)
	}
	root := repo_root(context.temp_allocator)
	name := fmt.aprintf("%s.json", selector, allocator = context.temp_allocator)
	return join_path({root, "scenarios", name}, allocator)
}
