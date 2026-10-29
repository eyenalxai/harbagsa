#+vet explicit-allocators
package bake

// One chart is one planar face with one normal, so a plain binomial kernel can
// never bleed across a surface; the gutter isolates neighbouring charts.
DENOISE_WEIGHTS :: [3]f32{0.25, 0.5, 0.25}

// A separable 3x3 binomial pass over one chart. It runs after the buried fill so
// every texel in the chart is covered and the weights stay uniform, and before
// the gutter so the copied edge already carries the filtered value.
lightmap_denoise_chart :: proc(
	atlas: []f32,
	chart: Chart,
	atlas_size: int,
	scratch: []f32,
) #no_bounds_check {
	for y in 0 ..< chart.height {
		for x in 0 ..< chart.width {
			left := clamp(x - 1, 0, chart.width - 1)
			right := clamp(x + 1, 0, chart.width - 1)
			row := (chart.y + y) * atlas_size + chart.x
			left_index := (row + left) * 4
			center_index := (row + x) * 4
			right_index := (row + right) * 4
			destination := (y * chart.width + x) * 3
			for channel in 0 ..< 3 {
				scratch[destination + channel] =
					DENOISE_WEIGHTS[0] * atlas[left_index + channel] +
					DENOISE_WEIGHTS[1] * atlas[center_index + channel] +
					DENOISE_WEIGHTS[2] * atlas[right_index + channel]
			}
		}
	}
	for y in 0 ..< chart.height {
		up := clamp(y - 1, 0, chart.height - 1)
		down := clamp(y + 1, 0, chart.height - 1)
		for x in 0 ..< chart.width {
			up_index := (up * chart.width + x) * 3
			center_index := (y * chart.width + x) * 3
			down_index := (down * chart.width + x) * 3
			destination := ((chart.y + y) * atlas_size + chart.x + x) * 4
			for channel in 0 ..< 3 {
				atlas[destination + channel] =
					DENOISE_WEIGHTS[0] * scratch[up_index + channel] +
					DENOISE_WEIGHTS[1] * scratch[center_index + channel] +
					DENOISE_WEIGHTS[2] * scratch[down_index + channel]
			}
		}
	}
}

denoise_scratch_len :: proc(layout: ^Atlas_Layout) -> int {
	largest := 0
	for chart in layout.charts {
		largest = max(largest, chart.width * chart.height)
	}
	return largest * 3
}
