#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:strings"

@(private)
compare_pairs :: proc(
	first, second: Run_Data,
	only: []string,
	allocator: mem.Allocator,
) -> ([]Compare_Pair, []string) {
	pairs := make([dynamic]Compare_Pair, 0, len(first.captures), allocator)
	errors := make([dynamic]string, 0, 4, allocator)
	for capture in first.captures {
		if len(only) > 0 && !string_in(capture.name, only) {
			continue
		}
		other, found := diff_capture_find(second.captures, capture.name)
		other_capture: Diff_Capture
		if found {
			other_capture = other^
		}
		pair := compare_pair_build(capture, other_capture, found, allocator)
		if !pair.ok {
			append(&errors, fmt.aprintf(
				"pair %q: %s",
				pair.name,
				pair.error,
				allocator = allocator,
			))
		}
		append(&pairs, pair)
	}
	for capture in second.captures {
		if len(only) > 0 && !string_in(capture.name, only) {
			continue
		}
		if _, found := diff_capture_find(first.captures, capture.name); found {
			continue
		}
		pair := compare_pair_build({}, capture, false, allocator)
		append(&errors, fmt.aprintf("pair %q: %s", pair.name, pair.error, allocator = allocator))
		append(&pairs, pair)
	}
	for name in only {
		found := false
		for pair in pairs {
			if pair.name == name {
				found = true
				break
			}
		}
		if found {
			continue
		}
		pair := Compare_Pair {
			name  = strings.clone(name, allocator),
			error = strings.clone("missing from both runs", allocator),
		}
		append(&errors, fmt.aprintf("pair %q: %s", name, pair.error, allocator = allocator))
		append(&pairs, pair)
	}
	return pairs[:], errors[:]
}

@(private)
compare_pair_build :: proc(
	first, second: Diff_Capture,
	has_second: bool,
	allocator: mem.Allocator,
) -> Compare_Pair {
	name := first.name != "" ? first.name : second.name
	pair := Compare_Pair{name = strings.clone(name, allocator)}
	if first.path == "" {
		pair.missing_a = true
		pair.error = strings.clone("missing capture in run A", allocator)
		return pair
	}
	if !has_second || second.path == "" {
		pair.missing_b = true
		pair.error = strings.clone("missing capture in run B", allocator)
		return pair
	}
	first_pixels, first_width, first_height, first_ok := load_png_rgba(first.path, allocator)
	defer delete(first_pixels, allocator)
	second_pixels, second_width, second_height, second_ok := load_png_rgba(second.path, allocator)
	defer delete(second_pixels, allocator)
	if !first_ok || !second_ok {
		pair.decode_error = true
		pair.error = strings.clone("cannot decode the PNG", allocator)
		return pair
	}
	if first_width != second_width || first_height != second_height {
		pair.size_mismatch = true
		pair.width = first_width
		pair.height = first_height
		pair.error = fmt.aprintf(
			"size mismatch: A is %dx%d, B is %dx%d",
			first_width,
			first_height,
			second_width,
			second_height,
			allocator = allocator,
		)
		return pair
	}
	diff := diff_pair_build(name, first_pixels, second_pixels, first_width, first_height)
	pair.ok = true
	pair.width = diff.width
	pair.height = diff.height
	pair.different_pixels = diff.different_pixels
	pair.max_delta = diff.max_delta
	pair.mean_delta = diff.mean_delta
	pair.over_16 = diff.over_16
	return pair
}

compare_pairs_ok :: proc(pairs: []Compare_Pair) -> bool {
	for pair in pairs {
		if !pair.ok {
			return false
		}
	}
	return true
}

compare_pairs_destroy :: proc(pairs: []Compare_Pair, allocator: mem.Allocator) {
	for pair in pairs {
		delete(pair.name, allocator)
		if pair.error != "" {
			delete(pair.error, allocator)
		}
	}
	delete(pairs, allocator)
}
