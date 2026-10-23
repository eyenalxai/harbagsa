#+vet explicit-allocators
package harness

import "core:fmt"

MAX_STEP_FRAMES :: 1_000_000
MAX_SESSION_LINE :: 1 << 20

format_error :: proc(format: string, args: ..any) -> string {
	return fmt.aprintf(format, ..args, allocator = context.allocator)
}

valid_capture_name :: proc(name: string) -> bool {
	if len(name) == 0 || len(name) > 128 {
		return false
	}
	for character in name {
		switch character {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '-', '_':
		case:
			return false
		}
	}
	return true
}
