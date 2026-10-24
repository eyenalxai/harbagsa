#+vet explicit-allocators
package harness

import "core:fmt"
import "core:strconv"
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
		stats_path := path[len("stats."):]
		if strings.has_prefix(stats_path, "region.") {
			region, has_region := capture.last_region.?
			if !has_region {
				return {}, format_error("%s", "the last capture has no region")
			}
			return capture_region_field(region, stats_path[len("region."):])
		}
		stats, has_stats := capture.last_stats.?
		if !has_stats {
			return {}, format_error("%s", "the last capture has no statistics")
		}
		return capture_stats_field(stats, stats_path)
	}
	if strings.has_prefix(path, "profile.") {
		profile, has_profile := capture.last_profile.?
		if !has_profile {
			return {}, format_error("%s", "the last capture has no profile")
		}
		return capture_profile_field(profile, path[len("profile."):])
	}
	if strings.has_prefix(path, "region.") {
		region, has_region := capture.last_region.?
		if !has_region {
			return {}, format_error("%s", "the last capture has no region")
		}
		return capture_region_field(region, path[len("region."):])
	}
	if strings.has_prefix(path, "crop.") {
		crop, has_crop := capture.last_crop.?
		if !has_crop {
			return {}, format_error("%s", "the last capture has no crop")
		}
		switch path[len("crop."):] {
		case "x":
			return {kind = .Number, number = f64(crop.x)}, ""
		case "y":
			return {kind = .Number, number = f64(crop.y)}, ""
		case "w":
			return {kind = .Number, number = f64(crop.w)}, ""
		case "h":
			return {kind = .Number, number = f64(crop.h)}, ""
		case "scale":
			return {kind = .Number, number = f64(crop.scale)}, ""
		case "width":
			return {kind = .Number, number = f64(crop.width)}, ""
		case "height":
			return {kind = .Number, number = f64(crop.height)}, ""
		}
		return {}, fmt.aprintf("unknown crop field %q", path, allocator = context.allocator)
	}
	if strings.has_prefix(path, "histogram.") {
		histogram, has_histogram := capture.last_histogram.?
		if !has_histogram {
			return {}, format_error("%s", "the last capture has no histogram")
		}
		return capture_histogram_field(histogram, path[len("histogram."):])
	}
	return {}, fmt.aprintf("unknown capture field %q", path, allocator = context.allocator)
}

@(private)
capture_region_field :: proc(region: Capture_Region, path: string) -> (Check_Value, string) {
	switch path {
	case "x":
		return {kind = .Number, number = f64(region.x)}, ""
	case "y":
		return {kind = .Number, number = f64(region.y)}, ""
	case "w":
		return {kind = .Number, number = f64(region.w)}, ""
	case "h":
		return {kind = .Number, number = f64(region.h)}, ""
	}
	return {}, fmt.aprintf("unknown region field %q", path, allocator = context.allocator)
}

@(private)
capture_profile_field :: proc(
	profile: Capture_Profile_Result,
	path: string,
) -> (Check_Value, string) {
	switch path {
	case "width":
		return {kind = .Number, number = f64(profile.width)}, ""
	case "low_index":
		return {kind = .Number, number = f64(profile.low_index)}, ""
	case "high_index":
		return {kind = .Number, number = f64(profile.high_index)}, ""
	case "flat":
		return {kind = .Bool, boolean = profile.flat}, ""
	case "axis":
		return {kind = .String, text = profile.axis}, ""
	case "channel":
		return {kind = .String, text = profile.channel}, ""
	}
	if strings.has_prefix(path, "values.") {
		index, parse_ok := strconv.parse_int(path[len("values."):])
		if !parse_ok || index < 0 || index >= len(profile.values) {
			return {}, fmt.aprintf("profile value index is out of range", allocator = context.allocator)
		}
		return {kind = .Number, number = f64(profile.values[index])}, ""
	}
	return {}, fmt.aprintf("unknown profile field %q", path, allocator = context.allocator)
}

@(private)
capture_histogram_field :: proc(
	histogram: Capture_Histogram_Result,
	path: string,
) -> (Check_Value, string) {
	if path == "bins" {
		return {kind = .Number, number = f64(histogram.bins)}, ""
	}
	channel_name, bin_text, has_bin := split_field(path)
	if !has_bin {
		return {}, fmt.aprintf("unknown histogram field %q", path, allocator = context.allocator)
	}
	bin, parse_ok := strconv.parse_int(bin_text)
	if !parse_ok || bin < 0 || bin >= histogram.bins {
		return {}, fmt.aprintf("histogram bin is out of range", allocator = context.allocator)
	}
	counts: []int
	switch channel_name {
	case "x":
		counts = histogram.x
	case "y":
		counts = histogram.y
	case "z":
		counts = histogram.z
	case "w":
		counts = histogram.w
	case:
		return {}, fmt.aprintf("unknown histogram channel %q", channel_name, allocator = context.allocator)
	}
	return {kind = .Number, number = f64(counts[bin])}, ""
}

@(private)
capture_stats_field :: proc(stats: Capture_Stats, path: string) -> (Check_Value, string) {
	if path == "velocity_median_texels" {
		median, has_median := stats.velocity_median_texels.?
		if !has_median {
			return {}, format_error("%s", "the last capture has no velocity median")
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

check_capture_window :: proc(captures: []Capture_Result, command: Check_Command) -> []Capture_Result {
	if !command.window.has {
		start := clamp(command.warmup, 0, len(captures))
		return captures[start:]
	}
	start := clamp(command.window.start, 0, len(captures))
	count := clamp(command.window.count, 0, len(captures) - start)
	return captures[start:start + count]
}
