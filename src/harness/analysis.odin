#+vet explicit-allocators
package harness

import "core:mem"

Analysis_Config :: struct {
	enabled:    bool,
	has_window: bool,
	start:      int,
	count:      int,
	maps:       bool,
}

analysis_config_default :: proc() -> Analysis_Config {
	return {enabled = true}
}

Analysis_Pair :: struct {
	from:             int   `json:"from"`,
	to:               int   `json:"to"`,
	mean:             f32   `json:"mean"`,
	max:              f32   `json:"max"`,
	over_16:          int   `json:"over_16"`,
	over_16_fraction: f32   `json:"over_16_fraction"`,
}

Analysis_Period :: struct {
	frames:      int   `json:"frames"`,
	correlation: f32   `json:"correlation"`,
}

Analysis_Summary :: struct {
	pairs:                  int             `json:"pairs"`,
	worst_mean:             f32             `json:"worst_mean"`,
	worst_max:              f32             `json:"worst_max"`,
	worst_over_16:          int             `json:"worst_over_16"`,
	worst_over_16_fraction: f32             `json:"worst_over_16_fraction"`,
	period:                 Analysis_Period `json:"period"`,
}

analysis_frames :: proc(captures: []Capture_Result, allocator: mem.Allocator) -> []Capture_Result {
	return filter_captures(captures, 0, 0, false, allocator)
}

@(private)
capture_matches :: proc(capture: Capture_Result, width, height: u32, by_size: bool) -> bool {
	if by_size {
		return capture.width == width && capture.height == height
	}
	return capture.target == "color" && capture.format == "png"
}

@(private)
filter_captures :: proc(
	items: []Capture_Result,
	width, height: u32,
	by_size: bool,
	allocator: mem.Allocator,
) -> []Capture_Result {
	count := 0
	for capture in items {
		if capture_matches(capture, width, height, by_size) {
			count += 1
		}
	}
	result := make([]Capture_Result, count, allocator)
	index := 0
	for capture in items {
		if capture_matches(capture, width, height, by_size) {
			result[index] = capture
			index += 1
		}
	}
	return result
}

analysis_window :: proc(frames: []Capture_Result, config: Analysis_Config) -> []Capture_Result {
	if len(frames) == 0 {
		return frames
	}
	start := 0
	count := len(frames)
	if config.has_window {
		start = clamp(config.start, 0, len(frames))
		count = clamp(config.count, 0, len(frames) - start)
	}
	return frames[start:start + count]
}

// A present run can be resized by the compositor. Only the frames that share
// the last frame's size are comparable, so the analysis keeps that run.
analysis_comparable :: proc(frames: []Capture_Result, allocator: mem.Allocator) -> []Capture_Result {
	if len(frames) == 0 {
		return nil
	}
	last := frames[len(frames) - 1]
	return filter_captures(frames, last.width, last.height, true, allocator)
}

analysis_summary :: proc(frames: []Capture_Result) -> Analysis_Summary {
	summary := Analysis_Summary{}
	if len(frames) < 2 {
		return summary
	}
	pairs := analysis_pairs(frames, context.temp_allocator)
	means := make([]f32, len(pairs), context.temp_allocator)
	for pair, index in pairs {
		means[index] = pair.mean
		summary.pairs += 1
		summary.worst_mean = max(summary.worst_mean, pair.mean)
		summary.worst_max = max(summary.worst_max, pair.max)
		summary.worst_over_16 = max(summary.worst_over_16, pair.over_16)
		summary.worst_over_16_fraction = max(
			summary.worst_over_16_fraction,
			pair.over_16_fraction,
		)
	}
	summary.period = analysis_period(means)
	return summary
}

@(private)
capture_delta_fraction :: proc(capture: Capture_Result) -> f32 {
	pixels := f32(capture.width) * f32(capture.height)
	if pixels <= 0 {
		return 0
	}
	return f32(capture.delta_over_16) / pixels
}

// The lag with the strongest positive autocorrelation. A static TAA scene
// repeats with the jitter period, so its mean delta repeats with that lag.
analysis_period :: proc(series: []f32) -> Analysis_Period {
	if len(series) < 4 {
		return {}
	}
	sum: f64
	for value in series {
		sum += f64(value)
	}
	mean := f32(sum / f64(len(series)))
	variance: f64
	for value in series {
		delta := f64(value - mean)
		variance += delta * delta
	}
	if variance <= 1e-12 {
		return {}
	}
	best_lag := 0
	best: f32
	for lag in 1 ..= len(series) / 2 {
		correlation := autocorrelation(series, mean, variance, lag)
		if correlation > best {
			best = correlation
			best_lag = lag
		}
	}
	if best_lag == 0 || best <= 0 {
		return {}
	}
	// A periodic series correlates at every multiple of its period. The
	// fundamental is the smallest lag that is nearly as strong as the best.
	threshold := best * 0.9
	fundamental := best_lag
	for lag in 1 ..= len(series) / 2 {
		if autocorrelation(series, mean, variance, lag) >= threshold {
			fundamental = lag
			break
		}
	}
	return {frames = fundamental, correlation = best}
}

@(private)
autocorrelation :: proc(series: []f32, mean: f32, variance: f64, lag: int) -> f32 {
	covariance: f64
	for index in lag ..< len(series) {
		covariance += f64((series[index] - mean) * (series[index - lag] - mean))
	}
	pairs := f64(len(series) - lag)
	return f32((covariance / pairs) / (variance / f64(len(series))))
}

session_refresh_analysis :: proc(session: ^Session) {
	session.has_analysis = false
	session.analysis = {}
	if !session.analysis_config.enabled || len(session.captures) == 0 {
		return
	}
	frames := analysis_frames(session.captures[:], session.allocator)
	defer delete(frames, session.allocator)
	window := analysis_window(frames, session.analysis_config)
	comparable := analysis_comparable(window, session.allocator)
	defer delete(comparable, session.allocator)
	session.analysis = analysis_summary(comparable)
	session.has_analysis = true
}

analysis_pairs :: proc(window: []Capture_Result, allocator: mem.Allocator) -> []Analysis_Pair {
	if len(window) < 2 {
		return nil
	}
	pairs := make([]Analysis_Pair, len(window) - 1, allocator)
	for capture, index in window {
		if index == 0 {
			continue
		}
		pairs[index - 1] = {
			from = window[index - 1].frame,
			to = capture.frame,
			mean = capture.delta_mean,
			max = f32(capture.delta_max),
			over_16 = capture.delta_over_16,
			over_16_fraction = capture_delta_fraction(capture),
		}
	}
	return pairs
}
