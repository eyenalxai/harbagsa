#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

Compare_Pair :: struct {
	name:             string `json:"name"`,
	ok:               bool   `json:"ok"`,
	missing_a:        bool   `json:"missing_a,omitempty"`,
	missing_b:        bool   `json:"missing_b,omitempty"`,
	size_mismatch:    bool   `json:"size_mismatch,omitempty"`,
	decode_error:     bool   `json:"decode_error,omitempty"`,
	width:            u32    `json:"width,omitempty"`,
	height:           u32    `json:"height,omitempty"`,
	different_pixels: int    `json:"different_pixels,omitempty"`,
	max_delta:        u8     `json:"max_delta,omitempty"`,
	mean_delta:       f32    `json:"mean_delta,omitempty"`,
	over_16:          int    `json:"over_16,omitempty"`,
	error:            string `json:"error,omitempty"`,
}

Compare_Report :: struct {
	ok:        bool           `json:"ok"`,
	run_a:     string         `json:"run_a"`,
	run_b:     string         `json:"run_b"`,
	out_dir:   string         `json:"out_dir"`,
	revision_a: string        `json:"revision_a"`,
	dirty_a:   bool           `json:"dirty_a"`,
	scenario_a: string        `json:"scenario_a"`,
	width_a:    u32           `json:"width_a,omitempty"`,
	height_a:   u32           `json:"height_a,omitempty"`,
	screenshots_a: int        `json:"screenshots_a,omitempty"`,
	revision_b: string        `json:"revision_b"`,
	dirty_b:   bool           `json:"dirty_b"`,
	scenario_b: string        `json:"scenario_b"`,
	width_b:    u32           `json:"width_b,omitempty"`,
	height_b:   u32           `json:"height_b,omitempty"`,
	screenshots_b: int        `json:"screenshots_b,omitempty"`,
	scale:      int           `json:"scale"`,
	delta:      bool          `json:"delta"`,
	pages:     []string       `json:"pages"`,
	pairs:     []Compare_Pair `json:"pairs"`,
}

@(private)
compare_runs_command :: proc(options: Compare_Options) -> int {
	first, first_error := run_data_load(options.run_a, context.allocator)
	if first_error != "" {
		return compare_error(first_error)
	}
	defer run_data_destroy(&first, context.allocator)
	second, second_error := run_data_load(options.run_b, context.allocator)
	if second_error != "" {
		return compare_error(second_error)
	}
	defer run_data_destroy(&second, context.allocator)

	only: []string
	if options.pairs != "" {
		only = strings.split(options.pairs, ",", context.temp_allocator)
		for name in only {
			if name == "" || !valid_capture_name(name) {
				return compare_error("--pairs names must use only letters, digits, '-' and '_'")
			}
		}
	}
	pairs, pair_errors := compare_pairs(first, second, only, context.allocator)
	defer compare_pairs_destroy(pairs, context.allocator)
	for message in pair_errors {
		delete(message, context.allocator)
	}
	delete(pair_errors, context.allocator)

	out_dir := options.out
	owned_out := false
	if out_dir == "" {
		out_dir = fmt.aprintf(
			"runs/compare/%s-vs-%s",
			filepath.stem(filepath.base(first.metadata.dir)),
			filepath.stem(filepath.base(second.metadata.dir)),
			allocator = context.allocator,
		)
		owned_out = true
	}
	defer if owned_out {
		delete(out_dir, context.allocator)
	}
	if refusal := compare_refuse_frames(out_dir, first.metadata.dir, second.metadata.dir); refusal != "" {
		return compare_error(refusal)
	}
	absolute_out, absolute_error := absolute_path(out_dir, context.allocator)
	if absolute_error != nil {
		return compare_error("cannot resolve the compare directory")
	}
	defer delete(absolute_out, context.allocator)
	if make_error := os.make_directory_all(absolute_out); make_error != nil && make_error != .Exist {
		return compare_error(fmt.aprintf(
			"cannot create %s: %v",
			absolute_out,
			make_error,
			allocator = context.temp_allocator,
		))
	}

	report := Compare_Report {
		run_a      = first.metadata.dir,
		run_b      = second.metadata.dir,
		out_dir    = absolute_out,
		revision_a = first.metadata.revision,
		dirty_a    = first.metadata.dirty,
		scenario_a = first.metadata.scenario,
		width_a    = first.metadata.width,
		height_a   = first.metadata.height,
		screenshots_a = first.metadata.screenshots,
		revision_b = second.metadata.revision,
		dirty_b    = second.metadata.dirty,
		scenario_b = second.metadata.scenario,
		width_b    = second.metadata.width,
		height_b   = second.metadata.height,
		screenshots_b = second.metadata.screenshots,
		scale      = max(options.scale, 1),
		delta      = options.delta,
		pairs      = pairs,
	}
	pages, page_error := compare_write_pages(
		&report,
		first,
		second,
		absolute_out,
		max(options.scale, 1),
		options.delta,
		context.allocator,
	)
	defer compare_pages_destroy(pages, context.allocator)
	if page_error != "" {
		return compare_error(page_error)
	}
	report.pages = pages
	report.ok = compare_pairs_ok(pairs)
	json_path := join_path({absolute_out, "compare.json"}, context.allocator)
	defer delete(json_path, context.allocator)
	if write_error := write_json_file(json_path, report); write_error != "" {
		return compare_error(write_error)
	}
	if options.json {
		data, marshal_error := json.marshal(report, {}, context.allocator)
		if marshal_error != nil {
			return compare_error("cannot encode the compare report")
		}
		defer delete(data, context.allocator)
		fmt.println(string(data))
	} else {
		compare_print_table(report)
	}
	return report.ok ? EXIT_OK : EXIT_CHECK
}

@(private)
compare_refuse_frames :: proc(out_dir, first, second: string) -> string {
	out, out_error := absolute_path(out_dir, context.temp_allocator)
	if out_error != nil {
		return "cannot resolve the compare directory"
	}
	runs := []string{first, second}
	for run in runs {
		frames := join_path({run, "frames"}, context.temp_allocator)
		absolute_frames, frames_error := absolute_path(frames, context.temp_allocator)
		if frames_error != nil {
			continue
		}
		if path_inside(out, absolute_frames) {
			return "compare cannot write inside a run's frames directory"
		}
	}
	return ""
}

@(private)
path_inside :: proc(path, root: string) -> bool {
	if path == root {
		return true
	}
	prefix := root
	if !strings.has_suffix(prefix, "/") {
		prefix = strings.concatenate({root, "/"}, context.temp_allocator)
	}
	return strings.has_prefix(path, prefix)
}

@(private)
compare_error :: proc(message: string) -> int {
	fmt.eprintf("harbagsa-agent compare: %s\n", message)
	print_compare_usage()
	return EXIT_SCENARIO
}

compare_print_table :: proc(report: Compare_Report) {
	fmt.printf("compare %s vs %s\n", report.run_a, report.run_b)
	fmt.printf(
		"A  %s  rev %s%s  %dx%d  %d captures  %s\n",
		report.scenario_a,
		report.revision_a,
		report.dirty_a ? " dirty" : "",
		report.width_a,
		report.height_a,
		report.screenshots_a,
		report.run_a,
	)
	fmt.printf(
		"B  %s  rev %s%s  %dx%d  %d captures  %s\n",
		report.scenario_b,
		report.revision_b,
		report.dirty_b ? " dirty" : "",
		report.width_b,
		report.height_b,
		report.screenshots_b,
		report.run_b,
	)
	fmt.printf("scale %d  delta %s\n", report.scale, report.delta ? "yes" : "no")
	failed := 0
	for pair in report.pairs {
		if !pair.ok {
			failed += 1
		}
	}
	fmt.printf("pairs: %d, failed: %d\n", len(report.pairs), failed)
	for pair in report.pairs {
		status := pair.ok ? "PASS" : "FAIL"
		if pair.ok {
			fmt.printf(
				"%s  %-28s %dx%d  different %d  max %d  mean %.3f  >16 %d\n",
				status,
				pair.name,
				pair.width,
				pair.height,
				pair.different_pixels,
				pair.max_delta,
				pair.mean_delta,
				pair.over_16,
			)
		} else {
			fmt.printf("%s  %-28s %s\n", status, pair.name, pair.error)
		}
	}
	for page in report.pages {
		fmt.printf("page: %s\n", page)
	}
	fmt.printf("report: %s\n", join_path({report.out_dir, "compare.json"}, context.temp_allocator))
}
