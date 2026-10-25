#+vet explicit-allocators
package harness

import "core:fmt"
import "core:log"
import "core:os"
import "core:strconv"
import "core:strings"

DEFAULT_WIDTH :: 1280
DEFAULT_HEIGHT :: 720
MAX_SIZE :: 16384
MAX_DEBUG_OVERRIDES :: 8

Debug_Override :: struct {
	key:   string,
	value: string,
}

Common_Options :: struct {
	out_dir:              string,
	tag:                  string,
	width:                u32,
	height:               u32,
	has_size:             bool,
	present:              bool,
	no_render:            bool,
	no_analysis:          bool,
	debug_renderer:       bool,
	verbose:              bool,
	debug_overrides:      [MAX_DEBUG_OVERRIDES]Debug_Override,
	debug_override_count: int,
}

Session_Options :: struct {
	using common: Common_Options,
	socket:       string,
}

cli_main :: proc() -> int {
	logger := log.create_console_logger(lowest = .Warning, allocator = context.allocator)
	context.logger = logger
	defer log.destroy_console_logger(logger, allocator = context.allocator)

	args := os.args[1:]
	if len(args) == 0 {
		print_usage()
		return EXIT_SCENARIO
	}
	switch args[0] {
	case "run":
		return cli_run(args[1:])
	case "session":
		return cli_session(args[1:])
	case "diff":
		return cli_diff(args[1:])
	case "ab":
		return cli_ab(args[1:])
	case "help", "--help", "-h":
		print_usage()
		return EXIT_OK
	}
	fmt.eprintf("harbagsa-agent: unknown command %q\n", args[0])
	print_usage()
	return EXIT_SCENARIO
}

cli_run :: proc(args: []string) -> int {
	options := Run_Options{common = {width = DEFAULT_WIDTH, height = DEFAULT_HEIGHT}}
	index := 0
	for index < len(args) {
		next, handled, option_error := parse_common_option(args, index, &options.common)
		if option_error != "" {
			return cli_error(option_error)
		}
		if handled {
			index = next
			continue
		}
		argument := args[index]
		if argument == "--param" {
			if index + 1 >= len(args) {
				return cli_error("--param needs NAME=VALUE[,VALUE...]")
			}
			if options.parameter_count >= MAX_SWEEP_PARAMETERS {
				return cli_error(fmt.aprintf(
					"--param accepts at most %d parameters",
					MAX_SWEEP_PARAMETERS,
					allocator = context.temp_allocator,
				))
			}
			sweep, sweep_error := parse_parameter_sweep(args[index + 1], context.allocator)
			if sweep_error != "" {
				return cli_error(sweep_error)
			}
			for existing in options.parameters[:options.parameter_count] {
				if existing.name == sweep.name {
					return cli_error(fmt.aprintf(
						"--param %s is given twice",
						sweep.name,
						allocator = context.temp_allocator,
					))
				}
			}
			options.parameters[options.parameter_count] = sweep
			options.parameter_count += 1
			index += 2
			continue
		}
		if strings.has_prefix(argument, "--") {
			return cli_error(fmt.aprintf("unknown option %q", argument, allocator = context.temp_allocator))
		}
		if options.scenario != "" {
			return cli_error("run takes one scenario")
		}
		options.scenario = argument
		index += 1
	}
	if options.scenario == "" {
		return cli_error("run needs a scenario file")
	}
	return run_batch(options)
}

cli_session :: proc(args: []string) -> int {
	options := Session_Options{common = {width = DEFAULT_WIDTH, height = DEFAULT_HEIGHT}}
	index := 0
	for index < len(args) {
		argument := args[index]
		if argument == "--socket" {
			if index + 1 >= len(args) {
				return cli_error("--socket needs a path")
			}
			options.socket = args[index + 1]
			index += 2
			continue
		}
		next, handled, option_error := parse_common_option(args, index, &options.common)
		if option_error != "" {
			return cli_error(option_error)
		}
		if handled {
			index = next
			continue
		}
		return cli_error(fmt.aprintf("unknown option %q", argument, allocator = context.temp_allocator))
	}
	return session_main(options)
}

@(private)
parse_common_option :: proc(
	args: []string,
	index: int,
	options: ^Common_Options,
) -> (
	next: int,
	handled: bool,
	error: string,
) {
	argument := args[index]
	switch argument {
	case "--out":
		if index + 1 >= len(args) {
			return index, true, "--out needs a directory"
		}
		options.out_dir = args[index + 1]
		return index + 2, true, ""
	case "--size":
		if index + 1 >= len(args) {
			return index, true, "--size needs WIDTHxHEIGHT"
		}
		width, height, ok := parse_size(args[index + 1])
		if !ok {
			return index, true, "--size must be WIDTHxHEIGHT"
		}
		options.width = width
		options.height = height
		options.has_size = true
		return index + 2, true, ""
	case "--tag":
		if index + 1 >= len(args) {
			return index, true, "--tag needs a name"
		}
		if !valid_capture_name(args[index + 1]) {
			return index, true, "--tag must use only letters, digits, '-' and '_'"
		}
		options.tag = args[index + 1]
		return index + 2, true, ""
	case "--renderer-debug":
		if index + 1 >= len(args) {
			return index, true, "--renderer-debug needs KEY=VALUE"
		}
		if options.debug_override_count >= MAX_DEBUG_OVERRIDES {
			return index, true, "--renderer-debug accepts at most 8 overrides"
		}
		override := args[index + 1]
		separator := strings.index_byte(override, '=')
		if separator <= 0 || separator + 1 >= len(override) {
			return index, true, "--renderer-debug needs KEY=VALUE"
		}
		key := override[:separator]
		if !valid_capture_name(key) {
			return index, true, "--renderer-debug needs a field name like sky"
		}
		options.debug_overrides[options.debug_override_count] = {
			key   = key,
			value = override[separator + 1:],
		}
		options.debug_override_count += 1
		return index + 2, true, ""
	case "--present":
		options.present = true
		return index + 1, true, ""
	case "--no-render":
		options.no_render = true
		return index + 1, true, ""
	case "--no-analysis":
		options.no_analysis = true
		return index + 1, true, ""
	case "--debug-renderer":
		options.debug_renderer = true
		return index + 1, true, ""
	case "--verbose", "--summary":
		options.verbose = true
		return index + 1, true, ""
	}
	return index, false, ""
}

parse_size :: proc(text: string) -> (width, height: u32, ok: bool) {
	separator := strings.index_byte(text, 'x')
	if separator <= 0 || separator + 1 >= len(text) {
		return 0, 0, false
	}
	width_value, width_ok := strconv.parse_u64(text[:separator])
	height_value, height_ok := strconv.parse_u64(text[separator + 1:])
	if !width_ok || !height_ok {
		return 0, 0, false
	}
	if width_value == 0 || height_value == 0 || width_value > MAX_SIZE || height_value > MAX_SIZE {
		return 0, 0, false
	}
	return u32(width_value), u32(height_value), true
}

@(private)
cli_error :: proc(message: string) -> int {
	print_summary_failure(message, EXIT_SCENARIO)
	return EXIT_SCENARIO
}

@(private)
print_usage :: proc() {
	fmt.eprintln("usage:")
	fmt.eprintln("  harbagsa-agent run <scenario.json|-> [--out DIR] [--tag NAME] [--param NAME=VALUE[,VALUE...]] [--size WxH] [--present] [--no-render] [--no-analysis] [--debug-renderer] [--renderer-debug KEY=VALUE] [--verbose]")
	fmt.eprintln("  harbagsa-agent session [--socket PATH] [--out DIR] [--size WxH] [--present] [--no-render] [--no-analysis] [--debug-renderer] [--renderer-debug KEY=VALUE]")
	fmt.eprintln("  harbagsa-agent diff <run-a> <run-b> [--max-pixels N] [--json]")
	fmt.eprintln("  harbagsa-agent ab [--base REF] [--scenario PATH] [--size WxH] [--runs N] [--prime SECONDS] [--out DIR]")
	fmt.eprintln("  harbagsa-agent help | -h | --help")
	fmt.eprintln("")
	fmt.eprintln("run - reads the scenario from standard input.")
	fmt.eprintln("--tag NAME appends NAME to the run directory so two runs coexist.")
	fmt.eprintln("--param NAME=VALUE overrides a scenario parameter; a comma list sweeps")
	fmt.eprintln("each value into its own run directory and writes sweep.json.")
	fmt.eprintln("run --verbose writes captures, checks, failures, setup, and perf to standard error;")
	fmt.eprintln("standard output stays one JSON line.")
	fmt.eprintln("perf takes {\"cmd\": \"perf\", \"frames\": N, \"warmup\": M, \"prime\": SECONDS, \"name\": \"label\", \"trace\": \"trace.jsonl\"}.")
	fmt.eprintln("diff pairs PNG captures by name. --max-pixels N exits 1 when a pair exceeds N;")
	fmt.eprintln("--json prints one machine-readable object.")
}
