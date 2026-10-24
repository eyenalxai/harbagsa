#+vet explicit-allocators
package harness

import "core:fmt"

import "src:perf"

MAX_STEP_FRAMES :: 1_000_000
MAX_SESSION_LINE :: 1 << 20

MAX_PERF_FRAMES :: perf.RING_CAPACITY
MAX_PERF_TRACE_PATH :: 1024
PERF_DEFAULT_FRAMES :: 120
PERF_DEFAULT_WARMUP :: 60

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
