#+vet explicit-allocators
package harness

// The longest and median identical-value run down the columns. Columns are the
// direction a horizontal band grows, and the median keeps one flat wall from
// hiding the band the gradient shows.
analysis_bands :: proc(image: []u8, width, height: u32) -> Analysis_Bands {
	bands := Analysis_Bands{columns = int(width)}
	if width == 0 || height == 0 || len(image) < int(width * height * 4) {
		return bands
	}
	run_histogram: [MAX_SIZE + 1]int
	levels: [256]bool
	run_total := 0
	for x in 0 ..< int(width) {
		previous := analysis_luma(image, int(width), x, 0)
		levels[previous] = true
		run := 1
		for y in 1 ..< int(height) {
			current := analysis_luma(image, int(width), x, y)
			levels[current] = true
			if current == previous {
				run += 1
				continue
			}
			run_histogram[run] += 1
			run_total += 1
			bands.longest_run = max(bands.longest_run, run)
			previous = current
			run = 1
		}
		run_histogram[run] += 1
		run_total += 1
		bands.longest_run = max(bands.longest_run, run)
	}
	for present in levels {
		if present {
			bands.levels += 1
		}
	}
	if run_total > 0 {
		target := run_total / 2
		seen := 0
		for count, run in run_histogram {
			seen += count
			if seen > target {
				bands.median_run = run
				break
			}
		}
	}
	return bands
}

@(private)
analysis_luma :: proc(image: []u8, width, x, y: int) -> int {
	base := (y * width + x) * 4
	return (int(image[base]) + int(image[base + 1]) + int(image[base + 2])) / 3
}
