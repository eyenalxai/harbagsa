#+vet explicit-allocators
#+vet !unused-procedures
package harness_test

import "core:os"
import "core:testing"

import "src:harness"

DIFF_PIXEL_DIR :: "/tmp/opencode/harbagsa-diff-pixels"
DIFF_CAPTURE_DIR :: "/tmp/opencode/harbagsa-diff-captures"

@(test)
diff_reports_identical_and_changed_pixels :: proc(t: ^testing.T) {
	_ = os.remove_all(DIFF_PIXEL_DIR)
	testing.expectf(
		t,
		os.make_directory_all(DIFF_PIXEL_DIR) == nil,
		"cannot create the test directory",
	)
	defer os.remove_all(DIFF_PIXEL_DIR)

	pixels: [16 * 4]u8
	for pixel in 0 ..< 16 {
		pixels[pixel * 4 + 0] = 10
		pixels[pixel * 4 + 1] = 20
		pixels[pixel * 4 + 2] = 30
		pixels[pixel * 4 + 3] = 255
	}
	changed := pixels
	changed[5 * 4 + 2] = 50

	base := write_test_png(t, DIFF_PIXEL_DIR, "base", pixels[:])
	defer harness.capture_result_destroy(&base, context.allocator)
	duplicate := write_test_png(t, DIFF_PIXEL_DIR, "copy", pixels[:])
	defer harness.capture_result_destroy(&duplicate, context.allocator)
	edited := write_test_png(t, DIFF_PIXEL_DIR, "edited", changed[:])
	defer harness.capture_result_destroy(&edited, context.allocator)

	base_pixels, width, height, base_ok := harness.load_png_rgba(base.path, context.allocator)
	defer delete(base_pixels, context.allocator)
	testing.expect(t, base_ok, "cannot decode the base PNG")
	copy_pixels, _, _, copy_ok := harness.load_png_rgba(duplicate.path, context.allocator)
	defer delete(copy_pixels, context.allocator)
	testing.expect(t, copy_ok, "cannot decode the copy PNG")
	changed_pixels, _, _, changed_ok := harness.load_png_rgba(edited.path, context.allocator)
	defer delete(changed_pixels, context.allocator)
	testing.expect(t, changed_ok, "cannot decode the changed PNG")
	testing.expect_value(t, width, u32(4))
	testing.expect_value(t, height, u32(4))

	identical := harness.diff_pair_build("copy", base_pixels, copy_pixels, width, height)
	testing.expect(t, identical.identical, "the copy is not identical")
	testing.expect_value(t, identical.different_pixels, 0)
	testing.expect_value(t, identical.max_delta, u8(0))

	different := harness.diff_pair_build("edited", base_pixels, changed_pixels, width, height)
	testing.expect(t, !different.identical, "the changed image is identical")
	testing.expect_value(t, different.different_pixels, 1)
	testing.expect_value(t, different.max_delta, u8(20))
	testing.expect_value(t, different.over_16, 1)
	testing.expect_value(t, different.mean_delta, f32(1.25))
}

@(test)
diff_captures_prefers_the_report_and_falls_back_to_frames :: proc(t: ^testing.T) {
	dir := DIFF_CAPTURE_DIR
	frames := "/tmp/opencode/harbagsa-diff-captures/frames"
	_ = os.remove_all(dir)
	testing.expectf(t, os.make_directory_all(frames) == nil, "cannot create the test directory")
	defer os.remove_all(dir)

	pixels: [16 * 4]u8
	for pixel in 0 ..< 16 {
		pixels[pixel * 4 + 0] = 1
		pixels[pixel * 4 + 1] = 2
		pixels[pixel * 4 + 2] = 3
		pixels[pixel * 4 + 3] = 255
	}
	first := write_test_png(t, frames, "first", pixels[:])
	defer harness.capture_result_destroy(&first, context.allocator)
	second := write_test_png(t, frames, "second", pixels[:])
	defer harness.capture_result_destroy(&second, context.allocator)

	captures, error := harness.diff_captures_load(dir, context.allocator)
	testing.expectf(t, error == "", "frames fallback failed: %s", error)
	defer harness.diff_captures_destroy(captures, context.allocator)
	testing.expect_value(t, len(captures), 2)
	if len(captures) == 2 {
		testing.expect_value(t, captures[0].name, "first")
		testing.expect_value(t, captures[1].name, "second")
	}

	report_path := "/tmp/opencode/harbagsa-diff-captures/report.json"
	report := `{"screenshots": [
		{"name": "first", "path": "/nonexistent/first.png", "format": "png"},
		{"name": "second", "format": "png"}
	]}`
	testing.expectf(t, os.write_entire_file(report_path, report) == nil, "cannot write the report")
	from_report, report_error := harness.diff_captures_load(dir, context.allocator)
	testing.expectf(t, report_error == "", "report load failed: %s", report_error)
	defer harness.diff_captures_destroy(from_report, context.allocator)
	testing.expect_value(t, len(from_report), 2)
	if len(from_report) == 2 {
		testing.expect(t, os.is_file(from_report[0].path), "the stale path did not fall back")
		testing.expect(t, os.is_file(from_report[1].path), "the empty path did not fall back")
	}
}

@(private)
write_test_png :: proc(
	t: ^testing.T,
	dir, name: string,
	pixels: []u8,
) -> harness.Capture_Result {
	result, error := harness.capture_write_png(
		dir,
		name,
		0,
		4,
		4,
		pixels,
		context.allocator,
	)
	testing.expectf(t, error == "", "cannot write %s: %s", name, error)
	return result
}
