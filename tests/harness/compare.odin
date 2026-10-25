#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

import "src:harness"

COMPARE_DIR :: "/tmp/opencode/harbagsa-compare"

@(test)
compare_writes_a_labeled_panel_and_report :: proc(t: ^testing.T) {
	out := COMPARE_DIR + "/panel"
	_ = os.remove_all(COMPARE_DIR)
	defer os.remove_all(COMPARE_DIR)
	first := COMPARE_DIR + "/first"
	second := COMPARE_DIR + "/second"
	write_compare_run(t, first, "shot", 4, 4, {10, 20, 30, 255}, "aaaaaaa", false)
	write_compare_run(t, second, "shot", 4, 4, {30, 40, 50, 255}, "bbbbbbb", true)

	code := harness.cli_compare([]string{first, second, "--out", out})
	testing.expect_value(t, code, 0)
	panel_path := fmt.aprintf("%s/compare.png", out, allocator = context.temp_allocator)
	testing.expect(t, os.is_file(panel_path), "the panel is missing")
	pixels, width, height, ok := harness.load_png_rgba(panel_path, context.allocator)
	defer delete(pixels, context.allocator)
	testing.expect(t, ok, "the panel does not decode")
	testing.expect(t, width > 100 && height > 100, "the panel is too small")


	report_path := fmt.aprintf("%s/compare.json", out, allocator = context.temp_allocator)
	data, read_error := os.read_entire_file(report_path, context.allocator)
	defer delete(data, context.allocator)
	testing.expectf(t, read_error == nil, "cannot read compare.json: %v", read_error)
	text := string(data)
	testing.expect(t, strings.contains(text, `"ok": true`), "the report is not ok")
	testing.expect(t, strings.contains(text, `"revision_a": "aaaaaaa"`), "the A revision is missing")
	testing.expect(t, strings.contains(text, `"dirty_b": true`), "the B dirty flag is missing")
}

@(test)
compare_rejects_a_missing_pair :: proc(t: ^testing.T) {
	out := COMPARE_DIR + "/missing"
	_ = os.remove_all(COMPARE_DIR)
	defer os.remove_all(COMPARE_DIR)
	first := COMPARE_DIR + "/first"
	second := COMPARE_DIR + "/second"
	write_compare_run(t, first, "shot", 4, 4, {10, 20, 30, 255}, "a", false)
	write_compare_run(t, second, "other", 4, 4, {10, 20, 30, 255}, "b", false)

	code := harness.cli_compare([]string{first, second, "--out", out, "--json"})
	testing.expect_value(t, code, 1)
	testing.expect(t, os.is_file(fmt.aprintf("%s/compare.png", out, allocator = context.temp_allocator)), "the panel is missing on a pair failure")
	data, read_error := os.read_entire_file(fmt.aprintf("%s/compare.json", out, allocator = context.temp_allocator), context.allocator)
	defer delete(data, context.allocator)
	testing.expectf(t, read_error == nil, "cannot read compare.json: %v", read_error)
	text := string(data)
	testing.expect(t, strings.contains(text, `"ok": false`), "the report says ok")
	testing.expect(t, strings.contains(text, `"missing_b": true`), "the missing pair was not reported")
}

@(test)
compare_reports_a_size_mismatch :: proc(t: ^testing.T) {
	out := COMPARE_DIR + "/size"
	_ = os.remove_all(COMPARE_DIR)
	defer os.remove_all(COMPARE_DIR)
	first := COMPARE_DIR + "/first"
	second := COMPARE_DIR + "/second"
	write_compare_run(t, first, "shot", 4, 4, {10, 20, 30, 255}, "a", false)
	write_compare_run(t, second, "shot", 8, 8, {10, 20, 30, 255}, "b", false)

	code := harness.cli_compare([]string{first, second, "--out", out, "--json"})
	testing.expect_value(t, code, 1)
	data, read_error := os.read_entire_file(fmt.aprintf("%s/compare.json", out, allocator = context.temp_allocator), context.allocator)
	defer delete(data, context.allocator)
	testing.expectf(t, read_error == nil, "cannot read compare.json: %v", read_error)
	testing.expect(t, strings.contains(string(data), `"size_mismatch": true`), "the size mismatch is missing")
}

@(test)
compare_selects_pairs_and_writes_a_delta_column :: proc(t: ^testing.T) {
	out := COMPARE_DIR + "/selected"
	_ = os.remove_all(COMPARE_DIR)
	defer os.remove_all(COMPARE_DIR)
	first := COMPARE_DIR + "/first"
	second := COMPARE_DIR + "/second"
	write_compare_run(t, first, "keep", 4, 4, {10, 20, 30, 255}, "a", false)
	write_compare_run(t, second, "keep", 4, 4, {30, 40, 50, 255}, "b", false)

	code := harness.cli_compare([]string {
		first,
		second,
		"--out",
		out,
		"--pairs",
		"keep",
		"--scale",
		"2",
		"--delta",
		"--json",
	})
	testing.expect_value(t, code, 0)
	report_path := fmt.aprintf("%s/compare.json", out, allocator = context.temp_allocator)
	data, read_error := os.read_entire_file(report_path, context.allocator)
	defer delete(data, context.allocator)
	testing.expectf(t, read_error == nil, "cannot read compare.json: %v", read_error)
	if read_error != nil {
		return
	}
	value, parse_error := json.parse_string(string(data), .JSON, true, context.temp_allocator)
	testing.expectf(t, parse_error == .None, "compare.json did not parse: %v", parse_error)
	object, object_ok := value.(json.Object)
	testing.expect(t, object_ok, "compare.json is not an object")
	if !object_ok {
		return
	}
	pairs, _ := object["pairs"].(json.Array)
	testing.expect_value(t, len(pairs), 1)
	testing.expect_value(t, object["scale"].(json.Integer), json.Integer(2))
	testing.expect_value(t, object["delta"].(json.Boolean), true)

	code = harness.cli_compare([]string{first, second, "--out", out, "--pairs", "missing"})
	testing.expect_value(t, code, 1)
	data, read_error = os.read_entire_file(report_path, context.allocator)
	testing.expectf(t, read_error == nil, "cannot read compare.json: %v", read_error)
	if read_error == nil {
		testing.expect(t, strings.contains(string(data), "missing from both runs"), "the missing pair is not named")
	}
}

@(test)
compare_refuses_a_frames_directory :: proc(t: ^testing.T) {
	out := COMPARE_DIR + "/first/frames/compare"
	_ = os.remove_all(COMPARE_DIR)
	defer os.remove_all(COMPARE_DIR)
	first := COMPARE_DIR + "/first"
	second := COMPARE_DIR + "/second"
	write_compare_run(t, first, "shot", 4, 4, {10, 20, 30, 255}, "a", false)
	write_compare_run(t, second, "shot", 4, 4, {10, 20, 30, 255}, "b", false)

	code := harness.cli_compare([]string{first, second, "--out", out})
	testing.expect_value(t, code, 2)
}

@(private)
write_compare_run :: proc(
	t: ^testing.T,
	dir, name: string,
	width, height: int,
	color: [4]u8,
	revision: string,
	dirty: bool,
) {
	frames := fmt.aprintf("%s/frames", dir, allocator = context.temp_allocator)
	testing.expectf(t, os.make_directory_all(frames) == nil, "cannot create %s", frames)
	pixels := make([]u8, width * height * 4, context.temp_allocator)
	for index := 0; index < width * height; index += 1 {
		pixels[index * 4 + 0] = color[0]
		pixels[index * 4 + 1] = color[1]
		pixels[index * 4 + 2] = color[2]
		pixels[index * 4 + 3] = 255
	}
	written, error := harness.capture_write_png(
		frames,
		name,
		0,
		u32(width),
		u32(height),
		pixels,
		context.allocator,
	)
	testing.expectf(t, error == "", "cannot write the capture: %s", error)
	defer harness.capture_result_destroy(&written, context.allocator)
	report := fmt.aprintf(
		`{{"scenario":{{"path":"scenarios/test.json"}},"setup":{{"revision":"%s","dirty":%v,"width":%d,"height":%d}},"captures":[{{"name":"%s","path":"%s","format":"png"}}]}}`,
		revision,
		dirty,
		width,
		height,
		name,
		written.path,
		allocator = context.temp_allocator,
	)
	testing.expectf(t, os.write_entire_file(fmt.aprintf("%s/report.json", dir, allocator = context.temp_allocator), report) == nil, "cannot write the report")
}
