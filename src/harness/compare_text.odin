#+vet explicit-allocators
package harness

import "core:strings"

// The compare panel only needs labels, so it carries its own 5x7 block font.
// Keeping it here avoids a dependency on a text backend the game no longer has.
Compare_Text :: struct {
	ok: bool,
}

GLYPH_WIDTH :: 5
GLYPH_HEIGHT :: 7
GLYPH_SCALE :: 2
GLYPH_ADVANCE :: (GLYPH_WIDTH + 1) * GLYPH_SCALE

compare_text_init :: proc() -> Compare_Text {
	return {ok = true}
}

compare_text_destroy :: proc(text: ^Compare_Text) {
	text^ = {}
}

@(private)
glyph_rows :: proc(character: byte) -> [GLYPH_HEIGHT]u8 {
	ch := character
	if ch >= 'a' && ch <= 'z' {
		ch -= 'a' - 'A'
	}
	switch ch {
	case 'A': return {0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001}
	case 'B': return {0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110}
	case 'C': return {0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110}
	case 'D': return {0b11100, 0b10010, 0b10001, 0b10001, 0b10001, 0b10010, 0b11100}
	case 'E': return {0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111}
	case 'F': return {0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000}
	case 'G': return {0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01110}
	case 'H': return {0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001}
	case 'I': return {0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110}
	case 'J': return {0b00111, 0b00010, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100}
	case 'K': return {0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001}
	case 'L': return {0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111}
	case 'M': return {0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001}
	case 'N': return {0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001}
	case 'O': return {0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110}
	case 'P': return {0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000}
	case 'Q': return {0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101}
	case 'R': return {0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001}
	case 'S': return {0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110}
	case 'T': return {0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100}
	case 'U': return {0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110}
	case 'V': return {0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100}
	case 'W': return {0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b10101, 0b01010}
	case 'X': return {0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001}
	case 'Y': return {0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100}
	case 'Z': return {0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111}
	case '0': return {0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110}
	case '1': return {0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110}
	case '2': return {0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111}
	case '3': return {0b11111, 0b00010, 0b00100, 0b00010, 0b00001, 0b10001, 0b01110}
	case '4': return {0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010}
	case '5': return {0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110}
	case '6': return {0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110}
	case '7': return {0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000}
	case '8': return {0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110}
	case '9': return {0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100}
	case '-': return {0, 0, 0, 0b11111, 0, 0, 0}
	case '.': return {0, 0, 0, 0, 0, 0b00110, 0b00110}
	case '/': return {0b00001, 0b00010, 0b00010, 0b00100, 0b01000, 0b01000, 0b10000}
	case '_': return {0, 0, 0, 0, 0, 0, 0b11111}
	case ':': return {0, 0b00110, 0b00110, 0, 0b00110, 0b00110, 0}
	case '>': return {0b10000, 0b01000, 0b00100, 0b00010, 0b00100, 0b01000, 0b10000}
	case '<': return {0b00001, 0b00010, 0b00100, 0b01000, 0b00100, 0b00010, 0b00001}
	case '%': return {0b11001, 0b11010, 0b00010, 0b00100, 0b01000, 0b01011, 0b10011}
	case ',': return {0, 0, 0, 0, 0b00110, 0b00110, 0b00100}
	case '(': return {0b00010, 0b00100, 0b01000, 0b01000, 0b01000, 0b00100, 0b00010}
	case ')': return {0b01000, 0b00100, 0b00010, 0b00010, 0b00010, 0b00100, 0b01000}
	case '[': return {0b01110, 0b01000, 0b01000, 0b01000, 0b01000, 0b01000, 0b01110}
	case ']': return {0b01110, 0b00010, 0b00010, 0b00010, 0b00010, 0b00010, 0b01110}
	case '#': return {0b01010, 0b01010, 0b11111, 0b01010, 0b11111, 0b01010, 0b01010}
	case '+': return {0, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0}
	case '=': return {0, 0, 0b11111, 0, 0b11111, 0, 0}
	case '*': return {0, 0b10101, 0b01110, 0b11111, 0b01110, 0b10101, 0}
	case '!': return {0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0, 0b00100}
	case '?': return {0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0, 0b00100}
	case ' ': return {0, 0, 0, 0, 0, 0, 0}
	}
	return {0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0, 0b00100}
}

compare_text_width :: proc(_: ^Compare_Text, value: string) -> int {
	columns := 0
	for character in value {
		if character & 0x80 != 0 {
			continue
		}
		columns += 1
	}
	return columns * GLYPH_ADVANCE
}

compare_text_fit :: proc(text: ^Compare_Text, value: string, max_width: int) -> string {
	if compare_text_width(text, value) <= max_width {
		return value
	}
	ellipsis := "..."
	width := max_width - compare_text_width(text, ellipsis)
	if width <= 0 {
		return ellipsis
	}
	cut := len(value)
	for cut > 0 {
		candidate := value[:cut]
		if compare_text_width(text, candidate) <= width {
			return strings.concatenate({candidate, ellipsis}, context.temp_allocator)
		}
		cut -= 1
	}
	return ellipsis
}

compare_text_draw :: proc(
	canvas: ^Compare_Canvas,
	text: ^Compare_Text,
	value: string,
	x, baseline: int,
	color: [4]u8,
) -> int {
	if !text.ok || value == "" {
		return 0
	}
	pen := x
	top := baseline - GLYPH_HEIGHT * GLYPH_SCALE
	for character in value {
		if character & 0x80 != 0 {
			continue
		}
		rows := glyph_rows(u8(character))
		for row in 0 ..< GLYPH_HEIGHT {
			for column in 0 ..< GLYPH_WIDTH {
				mask := u8(1) << u8(GLYPH_WIDTH - 1 - column)
				if rows[row] & mask == 0 {
					continue
				}
				for dy in 0 ..< GLYPH_SCALE {
					for dx in 0 ..< GLYPH_SCALE {
						compare_canvas_blend_pixel(
							canvas,
							pen + column * GLYPH_SCALE + dx,
							top + row * GLYPH_SCALE + dy,
							color,
							255,
						)
					}
				}
			}
		}
		pen += GLYPH_ADVANCE
	}
	return pen - x
}
