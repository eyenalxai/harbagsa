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

Common_Options :: struct {
	out_dir:        string,
	width:          u32,
	height:         u32,
	present:        bool,
	no_render:      bool,
	no_analysis:    bool,
	debug_renderer: bool,
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
	fmt.eprintln("  harbagsa-agent run <scenario.json> [--out DIR] [--size WxH] [--present] [--no-render] [--no-analysis] [--debug-renderer]")
	fmt.eprintln("  harbagsa-agent session [--socket PATH] [--out DIR] [--size WxH] [--present] [--no-render] [--no-analysis] [--debug-renderer]")
}
