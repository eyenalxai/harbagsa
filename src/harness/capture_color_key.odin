#+vet explicit-allocators
package harness

// A colour key counts the pixels close to one RGB value. Anti-aliasing and TAA
// move a pixel by a few levels, so the tolerance is a per-channel distance.
Capture_Color_Key :: struct {
	r:         u8,
	g:         u8,
	b:         u8,
	tolerance: f32,
}

Capture_Color_Key_Result :: struct {
	r:         u8    `json:"r"`,
	g:         u8    `json:"g"`,
	b:         u8    `json:"b"`,
	tolerance: f32   `json:"tolerance"`,
	matches:   int   `json:"matches"`,
	fraction:  f32   `json:"fraction"`,
}

// The colour key reads the same 0..255 channels the statistics do. A channel
// key on an intermediate target would compare linear values with 8-bit levels,
// so the parser keeps it on color captures.
capture_color_key_build :: proc(
	values: []f32,
	width, height: u32,
	region: Maybe(Capture_Region),
	key: Capture_Color_Key,
) -> Capture_Color_Key_Result {
	result := Capture_Color_Key_Result {
		r         = key.r,
		g         = key.g,
		b         = key.b,
		tolerance = key.tolerance,
	}
	x0, y0, x1, y1 := 0, 0, int(width), int(height)
	if bounds, has_region := region.?; has_region {
		x0, y0 = bounds.x, bounds.y
		x1, y1 = bounds.x + bounds.w, bounds.y + bounds.h
	}
	count := (x1 - x0) * (y1 - y0)
	if count <= 0 {
		return result
	}
	for y in y0 ..< y1 {
		for x in x0 ..< x1 {
			base := (y * int(width) + x) * 4
			if matches_color_key(values[base:base + 3], key) {
				result.matches += 1
			}
		}
	}
	result.fraction = f32(result.matches) / f32(count)
	return result
}

@(private)
matches_color_key :: proc(channels: []f32, key: Capture_Color_Key) -> bool {
	levels := [3]u8{key.r, key.g, key.b}
	for level, index in levels {
		value := channels[index]
		if value < 0 || value > 255 {
			return false
		}
		if abs(value - f32(level)) > key.tolerance {
			return false
		}
	}
	return true
}
