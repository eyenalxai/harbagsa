#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package frame_test

import "core:testing"

import "src:renderer"

@(test)
frame_ring_covers_each_corner_once_and_never_overlaps :: proc(t: ^testing.T) {
	theme := renderer.ui_theme_init(720)
	overlay := renderer.Overlay{theme = theme}
	overlay.hud_vertices = make([]renderer.HUD_Vertex, 64, context.allocator)
	defer delete(overlay.hud_vertices, context.allocator)

	x, y := f32(10), f32(20)
	width, height := f32(120), f32(60)
	thickness := max(theme.hairline * 2, 2)
	renderer.hud_emit_frame(&overlay, x, y, width, height, thickness, theme.line_hairline)

	rects: [8]Rect
	count := quads_with(overlay, theme.line_hairline, rects[:])
	testing.expect_value(t, count, 4)
	if count != 4 {
		return
	}

	for first in 0 ..< count {
		for second in first + 1 ..< count {
			a := rects[first]
			b := rects[second]
			overlap_x := min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
			overlap_y := min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
			testing.expectf(
				t,
				overlap_x <= 0 || overlap_y <= 0,
				"two ring edges overlap by %v x %v",
				overlap_x,
				overlap_y,
			)
		}
	}

	points := [8][2]f32 {
		{x + thickness * 0.5, y + thickness * 0.5},
		{x + width - thickness * 0.5, y + thickness * 0.5},
		{x + thickness * 0.5, y + height - thickness * 0.5},
		{x + width - thickness * 0.5, y + height - thickness * 0.5},
		{x + width * 0.5, y + thickness * 0.5},
		{x + width * 0.5, y + height - thickness * 0.5},
		{x + thickness * 0.5, y + height * 0.5},
		{x + width - thickness * 0.5, y + height * 0.5},
	}
	for point in points {
		covered := 0
		for rect in rects[:count] {
			if point.x >= rect.x &&
			   point.x < rect.x + rect.width &&
			   point.y >= rect.y &&
			   point.y < rect.y + rect.height {
				covered += 1
			}
		}
		testing.expectf(t, covered == 1, "point %v is covered %d times", point, covered)
	}
}
