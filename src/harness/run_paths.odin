#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:path/filepath"

// A tag appends a directory to the default or explicit run directory, so two
// runs with different tags coexist instead of replacing each other.
run_output_dir :: proc(
	scenario, out_dir, tag: string,
	allocator: mem.Allocator,
) -> (
	path: string,
	owned: bool,
) {
	if out_dir == "" {
		stem := scenario == "-" ? "stdin" : filepath.stem(scenario)
		path = fmt.aprintf("runs/%s", stem, allocator = allocator)
		owned = true
	} else {
		path = out_dir
	}
	if tag == "" {
		return path, owned
	}
	tagged := join_path({path, tag}, allocator)
	if owned {
		delete(path, allocator)
	}
	return tagged, true
}
