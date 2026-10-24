#+vet explicit-allocators
package harness

import "core:fmt"

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
	}
	return {}, fmt.aprintf("unknown analysis field %q", path, allocator = context.allocator)
}
