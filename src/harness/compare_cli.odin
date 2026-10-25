#+vet explicit-allocators
package harness

import "core:fmt"
import "core:strconv"
import "core:strings"

Compare_Options :: struct {
	run_a:     string,
	run_b:     string,
	out:       string,
	pairs:     string,
	json:      bool,
	delta:     bool,
	scale:     int,
}

cli_compare :: proc(args: []string) -> int {
	options: Compare_Options
	index := 0
	for index < len(args) {
		argument := args[index]
		switch {
		case argument == "--help" || argument == "-h":
			print_compare_usage()
			return EXIT_OK
		case argument == "--json":
			options.json = true
			index += 1
		case argument == "--delta":
			options.delta = true
			index += 1
		case argument == "--out":
			if index + 1 >= len(args) {
				return compare_error("--out needs a directory")
			}
			options.out = args[index + 1]
			index += 2
		case argument == "--pairs":
			if index + 1 >= len(args) {
				return compare_error("--pairs needs a comma-separated capture list")
			}
			options.pairs = args[index + 1]
			index += 2
		case argument == "--scale":
			if index + 1 >= len(args) {
				return compare_error("--scale needs a factor in [1, 8]")
			}
			scale, ok := strconv.parse_int(args[index + 1])
			if !ok || scale < 1 || scale > 8 {
				return compare_error("--scale must be an integer in [1, 8]")
			}
			options.scale = scale
			index += 2
		case strings.has_prefix(argument, "-"):
			return compare_error(fmt.aprintf(
				"unknown option %q",
				argument,
				allocator = context.temp_allocator,
			))
		case options.run_a == "":
			options.run_a = argument
			index += 1
		case options.run_b == "":
			options.run_b = argument
			index += 1
		case:
			return compare_error("compare takes two run directories")
		}
	}
	if options.run_a == "" || options.run_b == "" {
		return compare_error("compare takes two run directories")
	}
	return compare_runs_command(options)
}

@(private)
print_compare_usage :: proc() {
	fmt.eprintln("usage: harbagsa-agent compare <run-a> <run-b> [options]")
	fmt.eprintln("")
	fmt.eprintln("  --out DIR      output directory (default runs/compare/<a>-vs-<b>)")
	fmt.eprintln("  --pairs NAME,...  compare only the named captures")
	fmt.eprintln("  --scale N      allow up to N x upscaling for small captures (default 1)")
	fmt.eprintln("  --delta        add a difference column")
	fmt.eprintln("  --json         print one machine-readable object")
}

