#+vet explicit-allocators
#+vet !unused-procedures // the frame tests read the vertex stream through these
package frame_test

import "core:math"

import "src:renderer"

Rect :: struct {
	x, y, width, height: f32,
}

// Fills buffer with every quad drawn in one colour and returns the count. The
// tests read geometry, not pixels, so this is the only way to see the layout.
@(private)
quads_with :: proc(overlay: renderer.Overlay, color: [4]f32, buffer: []Rect) -> int {
	return quads_from_x(overlay, color, math.NEG_INF_F32, buffer)
}

// The same filter, but only quads whose left edge is at or right of min_x.
@(private)
quads_from_x :: proc(
	overlay: renderer.Overlay,
	color: [4]f32,
	min_x: f32,
	buffer: []Rect,
) -> int {
	count := 0
	for vertex in 0 ..< overlay.hud_count / 6 {
		if count >= len(buffer) {
			break
		}
		first := overlay.hud_vertices[vertex * 6]
		if first.color != color {
			continue
		}
		quad := rect_at(overlay, vertex * 6)
		if quad.width > 0 && quad.height > 0 && quad.x >= min_x {
			buffer[count] = quad
			count += 1
		}
	}
	return count
}

@(private)
widest_quad :: proc(overlay: renderer.Overlay, color: [4]f32) -> Rect {
	buffer: [64]Rect
	count := quads_with(overlay, color, buffer[:])
	best: Rect
	for quad in buffer[:count] {
		if quad.width * quad.height > best.width * best.height {
			best = quad
		}
	}
	return best
}

@(private)
bounds_of :: proc(overlay: renderer.Overlay, color: [4]f32) -> Rect {
	buffer: [64]Rect
	count := quads_with(overlay, color, buffer[:])
	if count == 0 {
		return {}
	}
	bounds := buffer[0]
	for quad in buffer[1:count] {
		right := max(bounds.x + bounds.width, quad.x + quad.width)
		bottom := max(bounds.y + bounds.height, quad.y + quad.height)
		bounds.x = min(bounds.x, quad.x)
		bounds.y = min(bounds.y, quad.y)
		bounds.width = right - bounds.x
		bounds.height = bottom - bounds.y
	}
	return bounds
}

@(private)
rect_at :: proc(overlay: renderer.Overlay, first: int) -> Rect {
	x0 := overlay.hud_vertices[first].position.x
	y0 := overlay.hud_vertices[first].position.y
	x1 := x0
	y1 := y0
	for offset in 1 ..< 6 {
		position := overlay.hud_vertices[first + offset].position
		x0 = min(x0, position.x)
		y0 = min(y0, position.y)
		x1 = max(x1, position.x)
		y1 = max(y1, position.y)
	}
	return {x = x0, y = y0, width = x1 - x0, height = y1 - y0}
}
