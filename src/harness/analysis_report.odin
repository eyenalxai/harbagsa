#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"

ANALYSIS_WORST_PIXELS :: 8

Analysis_Window :: struct {
	start: int `json:"start"`,
	count: int `json:"count"`,
}

Analysis_Pixel :: struct {
	x:      int     `json:"x"`,
	y:      int     `json:"y"`,
	mean:   f32     `json:"mean"`,
	series: []f32   `json:"series"`,
}

Analysis_Maps :: struct {
	diff:     string `json:"diff"`,
	variance: string `json:"variance"`,
}

Analysis_Report :: struct {
	window:       Analysis_Window  `json:"window"`,
	frames:       []int            `json:"frames"`,
	pairs:        []Analysis_Pair  `json:"pairs"`,
	summary:      Analysis_Summary `json:"summary"`,
	worst_pixels: []Analysis_Pixel `json:"worst_pixels"`,
	maps:         Maybe(Analysis_Maps) `json:"maps,omitempty"`,
}

Worst_Pixel :: struct {
	index:    int,
	variance: f32,
}

// The maps are diagnostic images of the analysis window, so they live beside
// the captures. The report carries their final paths.
write_analysis :: proc(
	staging_dir, staging_frames_dir, final_dir, final_frames_dir: string,
	captures: []Capture_Result,
	config: Analysis_Config,
	allocator: mem.Allocator,
) -> (
	path: string,
	error: string,
) {
	frames := analysis_frames(captures, allocator)
	defer delete(frames, allocator)
	if !config.enabled || len(captures) == 0 {
		return "", ""
	}
	window := analysis_window(frames, config)
	comparable := analysis_comparable(window, allocator)
	defer delete(comparable, allocator)
	window = comparable
	if len(window) == 0 {
		staging_path := join_path({staging_dir, "analysis.json"}, allocator)
		report := Analysis_Report {
			window = {start = config.start, count = 0},
			frames = make([]int, 0, allocator),
			pairs = make([]Analysis_Pair, 0, allocator),
			summary = analysis_summary(window),
			worst_pixels = make([]Analysis_Pixel, 0, allocator),
		}
		defer {
			delete(report.frames, allocator)
			delete(report.pairs, allocator)
			delete(report.worst_pixels, allocator)
		}
		if write_error := write_json_file(staging_path, report); write_error != "" {
			delete(staging_path, allocator)
			return "", write_error
		}
		delete(staging_path, allocator)
		return join_path({final_dir, "analysis.json"}, allocator), ""
	}

	first_width := window[0].width
	first_height := window[0].height
	pixels := int(first_width) * int(first_height)
	if pixels == 0 {
		return "", format_error("analysis frame has no pixels")
	}
	sum := make([]f64, pixels, allocator)
	defer delete(sum, allocator)
	squares := make([]f64, pixels, allocator)
	defer delete(squares, allocator)
	first_pixels := make([]u8, pixels * 4, allocator)
	defer delete(first_pixels, allocator)
	last_pixels := make([]u8, pixels * 4, allocator)
	defer delete(last_pixels, allocator)

	for capture, index in window {
		image, width, height, image_ok := analysis_load_png(capture.path, allocator)
		if !image_ok {
			return "", fmt.aprintf("cannot decode %s", capture.path, allocator = allocator)
		}
		if width != first_width || height != first_height {
			delete(image, allocator)
			return "", format_error("analysis frames differ in size")
		}
		for pixel in 0 ..< pixels {
			base := pixel * 4
			luma := (f64(image[base]) + f64(image[base + 1]) + f64(image[base + 2])) / 3
			sum[pixel] += luma
			squares[pixel] += luma * luma
		}
		if index == 0 {
			copy(first_pixels, image)
		}
		if index == len(window) - 1 {
			copy(last_pixels, image)
		}
		delete(image, allocator)
	}

	worst: [ANALYSIS_WORST_PIXELS]Worst_Pixel
	worst_count := 0
	variances := make([]f32, pixels, allocator)
	defer delete(variances, allocator)
	max_variance: f32
	frame_count := f64(len(window))
	for pixel in 0 ..< pixels {
		mean := sum[pixel] / frame_count
		variance := max(squares[pixel] / frame_count - mean * mean, 0)
		variances[pixel] = f32(variance)
		max_variance = max(max_variance, variances[pixel])
		if variance > 0 {
			worst_count = worst_pixel_insert(&worst, worst_count, {index = pixel, variance = f32(variance)})
		}
	}

	worst_pixels := make([dynamic]Analysis_Pixel, 0, worst_count, allocator)
	defer {
		for &pixel in worst_pixels {
			delete(pixel.series, allocator)
		}
		delete(worst_pixels)
	}
	for entry in worst[:worst_count] {
		append(
			&worst_pixels,
			Analysis_Pixel {
				x = entry.index % int(first_width),
				y = entry.index / int(first_width),
				series = make([]f32, len(window), allocator),
			},
		)
	}
	if worst_count > 0 {
		for capture, index in window {
			image, _, _, image_ok := analysis_load_png(capture.path, allocator)
			if !image_ok {
				return "", fmt.aprintf("cannot decode %s", capture.path, allocator = allocator)
			}
			for &pixel in worst_pixels {
				base := (pixel.y * int(first_width) + pixel.x) * 4
				luma := (f32(image[base]) + f32(image[base + 1]) + f32(image[base + 2])) / 3
				pixel.series[index] = luma
			}
			delete(image, allocator)
		}
		for &pixel in worst_pixels {
			total: f32
			for value in pixel.series {
				total += value
			}
			pixel.mean = total / f32(len(pixel.series))
		}
	}

	summary := analysis_summary(window)
	if region, has_region := config.region.?; has_region {
		if !capture_region_valid(region, first_width, first_height) {
			return "", format_error("analysis region must be inside the capture")
		}
	}
	summary.bands = analysis_bands(last_pixels, first_width, first_height, config.region)
	report := Analysis_Report {
		window = {start = config.start, count = len(window)},
		pairs = analysis_pairs(window, allocator),
		summary = summary,
		worst_pixels = worst_pixels[:],
	}
	defer delete(report.pairs, allocator)
	report.frames = make([]int, len(window), allocator)
	defer delete(report.frames, allocator)
	for capture, index in window {
		report.frames[index] = capture.frame
	}

	if config.maps {
		maps, maps_error := analysis_write_maps(
			staging_frames_dir,
			final_frames_dir,
			first_pixels,
			last_pixels,
			variances,
			max_variance,
			first_width,
			first_height,
			allocator,
		)
		if maps_error != "" {
			return "", maps_error
		}
		report.maps = maps
	}

	staging_path := join_path({staging_dir, "analysis.json"}, allocator)
	if write_error := write_json_file(staging_path, report); write_error != "" {
		delete(staging_path, allocator)
		return "", write_error
	}
	delete(staging_path, allocator)
	return join_path({final_dir, "analysis.json"}, allocator), ""
}

@(private)
worst_pixel_insert :: proc(worst: ^[ANALYSIS_WORST_PIXELS]Worst_Pixel, count: int, value: Worst_Pixel) -> int {
	position := count
	if position > len(worst) - 1 {
		position = len(worst) - 1
		if value.variance <= worst[position].variance {
			return count
		}
	}
	for position > 0 && worst[position - 1].variance < value.variance {
		worst[position] = worst[position - 1]
		position -= 1
	}
	worst[position] = value
	return min(count + 1, len(worst))
}
