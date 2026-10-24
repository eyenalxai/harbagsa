#+vet explicit-allocators
package harness

import "core:fmt"
import "core:strings"

@(private)
capture_field :: proc(capture: Capture_Summary, path: string) -> (Check_Value, string) {
	switch path {
	case "count":
		return {kind = .Number, number = f64(capture.count)}, ""
	case "worst_mean_delta":
		return {kind = .Number, number = f64(capture.worst_mean_delta)}, ""
	case "worst_max_delta":
		return {kind = .Number, number = f64(capture.worst_max_delta)}, ""
	case "worst_over_16":
		return {kind = .Number, number = f64(capture.worst_over_16)}, ""
	case "worst_over_16_fraction":
		return {kind = .Number, number = f64(capture.worst_over_16_fraction)}, ""
	case "target":
		return {kind = .String, text = capture.last_target}, ""
	case "format":
		return {kind = .String, text = capture.last_format}, ""
	}
	if strings.has_prefix(path, "stats.") {
		stats, has_stats := capture.last_stats.?
		if !has_stats {
			return {}, "the last capture has no statistics"
		}
		return capture_stats_field(stats, path[len("stats."):])
	}
	return {}, fmt.aprintf("unknown capture field %q", path, allocator = context.allocator)
}

@(private)
capture_stats_field :: proc(stats: Capture_Stats, path: string) -> (Check_Value, string) {
	if path == "velocity_median_texels" {
		median, has_median := stats.velocity_median_texels.?
		if !has_median {
			return {}, "the last capture has no velocity median"
		}
		return {kind = .Number, number = f64(median)}, ""
	}
	head, tail, has_tail := split_field(path)
	if !has_tail {
		return {}, fmt.aprintf("unknown capture statistics field %q", path, allocator = context.allocator)
	}
	channel, channel_ok := capture_channel_index(tail)
	if !channel_ok {
		return {}, fmt.aprintf("unknown capture statistics channel %q", tail, allocator = context.allocator)
	}
	value: f32
	switch head {
	case "min":
		value = stats.min[channel]
	case "max":
		value = stats.max[channel]
	case "mean":
		value = stats.mean[channel]
	case:
		return {}, fmt.aprintf("unknown capture statistics field %q", path, allocator = context.allocator)
	}
	return {kind = .Number, number = f64(value)}, ""
}

@(private)
capture_channel_index :: proc(axis: string) -> (int, bool) {
	switch axis {
	case "x":
		return 0, true
	case "y":
		return 1, true
	case "z":
		return 2, true
	case "w":
		return 3, true
	}
	return 0, false
}
