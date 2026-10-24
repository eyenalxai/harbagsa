#+vet explicit-allocators
package game

LINE_BUFFER_MAX_LINES :: 16
LINE_BUFFER_LINE_BYTES :: 96

Line_Buffer :: struct {
	lines:   [LINE_BUFFER_MAX_LINES]string,
	count:   int,
	storage: [LINE_BUFFER_MAX_LINES][LINE_BUFFER_LINE_BYTES]u8,
}
