#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"

// The wrapper owns the flag names and tools/ab.sh owns the benchmark. Keeping
// the translation here means the script stays usable on its own.
ab_build_args :: proc(
	args: []string,
	allocator: mem.Allocator,
) -> (
	argv: []string,
	error: string,
) {
	translated := make([dynamic]string, 0, len(args), allocator)
	index := 0
	for index < len(args) {
		argument := args[index]
		switch argument {
		case "-h", "--help":
			append(&translated, "--help")
			index += 1
		case "--base", "--ref":
			value, next, value_error := ab_option_value(args, index, allocator)
			if value_error != "" {
				delete(translated)
				return nil, value_error
			}
			append(&translated, "--ref")
			append(&translated, value)
			index = next
		case "--scenario", "--size", "--runs", "--prime", "--out":
			value, next, value_error := ab_option_value(args, index, allocator)
			if value_error != "" {
				delete(translated)
				return nil, value_error
			}
			append(&translated, argument)
			append(&translated, value)
			index = next
		case:
			delete(translated)
			return nil, fmt.aprintf("unknown option %q", argument, allocator = allocator)
		}
	}
	return translated[:], ""
}

cli_ab :: proc(args: []string) -> int {
	argv, argument_error := ab_build_args(args, context.allocator)
	defer delete(argv, context.allocator)
	if argument_error != "" {
		fmt.eprintf("harbagsa-agent ab: %s\n", argument_error)
		delete(argument_error, context.allocator)
		print_ab_usage()
		return EXIT_SCENARIO
	}
	if ab_help_requested(argv) {
		print_ab_usage()
		return EXIT_OK
	}
	script, script_error := ab_script_path(context.allocator)
	if script_error != "" {
		fmt.eprintf("harbagsa-agent ab: %s\n", script_error)
		delete(script_error, context.allocator)
		return EXIT_SCENARIO
	}
	defer delete(script, context.allocator)
	return ab_exec(script, argv)
}

@(private)
ab_option_value :: proc(
	args: []string,
	index: int,
	allocator: mem.Allocator,
) -> (
	value: string,
	next: int,
	error: string,
) {
	if index + 1 >= len(args) {
		return "", index, fmt.aprintf("%s needs a value", args[index], allocator = allocator)
	}
	return args[index + 1], index + 2, ""
}

@(private)
ab_help_requested :: proc(argv: []string) -> bool {
	for argument in argv {
		if argument == "--help" {
			return true
		}
	}
	return false
}

// The agent may run from a subdirectory, so the script is located from the
// working directory upward rather than from the build output.
@(private)
ab_script_path :: proc(allocator: mem.Allocator) -> (path: string, error: string) {
	directory, directory_error := os.get_working_directory(allocator)
	if directory_error != nil {
		return "", fmt.aprintf(
			"cannot read the working directory: %v",
			directory_error,
			allocator = allocator,
		)
	}
	defer delete(directory, allocator)

	current := directory
	for {
		candidate, join_error := filepath.join({current, "tools", "ab.sh"}, allocator)
		if join_error != nil {
			return "", fmt.aprintf("cannot resolve tools/ab.sh: %v", join_error, allocator = allocator)
		}
		if os.is_file(candidate) {
			return candidate, ""
		}
		delete(candidate, allocator)
		parent := filepath.dir(current)
		if parent == current {
			break
		}
		current = parent
	}
	return "", fmt.aprintf("cannot find tools/ab.sh above %s", directory, allocator = allocator)
}

@(private)
ab_exec :: proc(script: string, argv: []string) -> int {
	command := make([]string, len(argv) + 2, context.allocator)
	defer delete(command, context.allocator)
	command[0] = "sh"
	command[1] = script
	copy(command[2:], argv)

	process, start_error := os.process_start({
		command = command,
		stdin = os.stdin,
		stdout = os.stdout,
		stderr = os.stderr,
	})
	if start_error != nil {
		fmt.eprintf("harbagsa-agent ab: cannot run %s: %v\n", script, start_error)
		return EXIT_SCENARIO
	}
	state, wait_error := os.process_wait(process)
	if wait_error != nil {
		fmt.eprintf("harbagsa-agent ab: cannot wait for %s: %v\n", script, wait_error)
		return EXIT_SCENARIO
	}
	return state.exit_code
}

@(private)
print_ab_usage :: proc() {
	fmt.println("usage: harbagsa-agent ab [options]")
	fmt.println("")
	fmt.println("  --base REF        base git ref (default origin/main)")
	fmt.println("  --ref REF         same as --base; passed through")
	fmt.println("  --scenario PATH   perf scenario; repeatable (default scenarios/perf.json)")
	fmt.println("  --size WxH        offscreen extent (default 2560x1440)")
	fmt.println("  --runs N          pairs per scenario (default 5)")
	fmt.println("  --prime SECONDS   time-based prime for every perf command (default 2.0)")
	fmt.println("  --out DIR         output directory (default runs/ab)")
	fmt.println("  -h, --help        print this usage")
	fmt.println("")
	fmt.println("The run delegates to tools/ab.sh and needs python3 and flock.")
}
