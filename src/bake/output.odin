#+vet explicit-allocators
#+vet !unused-procedures // the tool and the harness share this writer
package bake

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

// Write an artifact through a temporary file so a failed write never leaves a
// half-written bake at the load path.
write_file :: proc(path: string, bytes: []u8) -> string {
	directory := filepath.dir(path)
	if directory != "" && directory != "." && !os.is_dir(directory) {
		if mkdir_error := os.mkdir_all(directory); mkdir_error != nil {
			return fmt.aprintf(
				"cannot create %s: %v",
				directory,
				mkdir_error,
				allocator = context.allocator,
			)
		}
	}
	temporary := strings.concatenate({path, ".tmp"}, context.allocator)
	defer delete(temporary, context.allocator)
	if write_error := os.write_entire_file(temporary, bytes); write_error != nil {
		return fmt.aprintf(
			"cannot write %s: %v",
			temporary,
			write_error,
			allocator = context.allocator,
		)
	}
	if rename_error := os.rename(temporary, path); rename_error != nil {
		_ = os.remove(temporary)
		return fmt.aprintf(
			"cannot publish %s: %v",
			path,
			rename_error,
			allocator = context.allocator,
		)
	}
	return ""
}
