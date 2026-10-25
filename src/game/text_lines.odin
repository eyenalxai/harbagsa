#+vet explicit-allocators
package game

import "core:fmt"

LINE_BUFFER_MAX_LINES :: 16
LINE_BUFFER_LINE_BYTES :: 160

Line_Buffer :: struct {
	storage: [LINE_BUFFER_MAX_LINES][LINE_BUFFER_LINE_BYTES]u8,
}

// One place that writes a formatted line into fixed storage, so a row never
// owns memory and never allocates while the simulation runs.
line_format :: proc(buffer: ^Line_Buffer, index: int, format: string, args: ..any) -> string {
	return fmt.bprintf(buffer.storage[index][:], format, ..args)
}
