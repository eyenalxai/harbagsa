#+vet explicit-allocators
package harness

import "core:fmt"
import "core:strings"

@(private)
analysis_field :: proc(analysis: Analysis_Summary, path: string) -> (Check_Value, string) {
	switch path {
	case "pairs":
		return {kind = .Number, number = f64(analysis.pairs)}, ""
	case "worst_mean":
		return {kind = .Number, number = f64(analysis.worst_mean)}, ""
	case "worst_max":
		return {kind = .Number, number = f64(analysis.worst_max)}, ""
	case "worst_over_16":
		return {kind = .Number, number = f64(analysis.worst_over_16)}, ""
	case "worst_over_16_fraction":
		return {kind = .Number, number = f64(analysis.worst_over_16_fraction)}, ""
	case "period.frames":
		return {kind = .Number, number = f64(analysis.period.frames)}, ""
	case "period.correlation":
		return {kind = .Number, number = f64(analysis.period.correlation)}, ""
	case "bands.longest_run":
		return {kind = .Number, number = f64(analysis.bands.longest_run)}, ""
	case "bands.median_run":
		return {kind = .Number, number = f64(analysis.bands.median_run)}, ""
	case "bands.levels":
		return {kind = .Number, number = f64(analysis.bands.levels)}, ""
	case "bands.columns":
		return {kind = .Number, number = f64(analysis.bands.columns)}, ""
	}
	if strings.has_prefix(path, "bands.region.") {
		region, has_region := analysis.bands.region.?
		if !has_region {
			return {}, format_error("%s", "the analysis bands have no region")
		}
		return capture_region_field(region, path[len("bands.region."):])
	}
	return {}, fmt.aprintf("unknown analysis field %q", path, allocator = context.allocator)
}
