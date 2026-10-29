#+vet explicit-allocators
package bake

// A separable 3x3 binomial pass over one chart. It runs after the buried fill so
// every texel in the chart is covered and the weights stay uniform, and before
// the gutter so the copied edge already carries the filtered value. One chart is
// one planar face, so the kernel cannot bleed across a surface.
lightmap_denoise_chart :: proc(
	atlas: []f32,
	chart: Chart,
	atlas_size: int,
	scratch: []f32,
) #no_bounds_check {
	for y in 0 ..< chart.height {
		for x in 0 ..< chart.width {
			row := (chart.y + y) * atlas_size + chart.x
			left := (row + clamp(x - 1, 0, chart.width - 1)) * 4
			center := (row + x) * 4
			right := (row + clamp(x + 1, 0, chart.width - 1)) * 4
			destination := (y * chart.width + x) * 3
			for channel in 0 ..< 3 {
				scratch[destination + channel] = binomial3(
					atlas[left + channel],
					atlas[center + channel],
					atlas[right + channel],
				)
			}
		}
	}
	for y in 0 ..< chart.height {
		up := clamp(y - 1, 0, chart.height - 1) * chart.width
		center := y * chart.width
		down := clamp(y + 1, 0, chart.height - 1) * chart.width
		for x in 0 ..< chart.width {
			destination := ((chart.y + y) * atlas_size + chart.x + x) * 4
			for channel in 0 ..< 3 {
				atlas[destination + channel] = binomial3(
					scratch[(up + x) * 3 + channel],
					scratch[(center + x) * 3 + channel],
					scratch[(down + x) * 3 + channel],
				)
			}
		}
	}
}

@(private)
binomial3 :: proc(left, center, right: f32) -> f32 {
	return 0.25 * left + 0.5 * center + 0.25 * right
}

denoise_scratch_len :: proc(layout: ^Atlas_Layout) -> int {
	largest := 0
	for chart in layout.charts {
		largest = max(largest, chart.width * chart.height)
	}
	return largest * 3
}
