#+vet explicit-allocators
package harness

import "core:fmt"

print_run_usage :: proc() {
	fmt.eprintln("usage: harbagsa-agent run <scenario.json|-> [options]")
	fmt.eprintln("")
	fmt.eprintln("  --out DIR         replace this run directory atomically")
	fmt.eprintln("  --tag NAME        append NAME to the run directory")
	fmt.eprintln("  --param NAME=...  override a scenario parameter; a comma list sweeps")
	fmt.eprintln("  --size WxH        capture extent (default 1280x720)")
	fmt.eprintln("  --present         render the real window and capture the swapchain")
	fmt.eprintln("  --no-render       simulation and checks only")
	fmt.eprintln("  --no-analysis     skip analysis.json and the analysis maps")
	fmt.eprintln("  --debug-renderer  accept renderer_debug commands")
	fmt.eprintln("  --renderer-debug KEY=VALUE  apply a gated override before the commands")
	fmt.eprintln("  --timeout SECONDS  stop the run when it exceeds this wall-clock budget")
	fmt.eprintln("  --summary         write the check table and capture paths to stderr")
	fmt.eprintln("  --verbose         write captures, checks, setup, and perf to stderr")
	fmt.eprintln("")
	fmt.eprintln("run - reads the scenario from standard input.")
}

print_session_usage :: proc() {
	fmt.eprintln("usage: harbagsa-agent session [options]")
	fmt.eprintln("")
	fmt.eprintln("  --socket PATH     serve the session over a Unix socket")
	fmt.eprintln("  --out DIR         capture directory (default runs/session)")
	fmt.eprintln("  --size WxH        capture extent (default 1280x720)")
	fmt.eprintln("  --present         render the real window")
	fmt.eprintln("  --no-render       simulation and checks only")
	fmt.eprintln("  --no-analysis     skip the analysis report")
	fmt.eprintln("  --debug-renderer  accept renderer_debug commands")
	fmt.eprintln("  --renderer-debug KEY=VALUE  apply a gated override")
	fmt.eprintln("  --timeout SECONDS  stop the session when it exceeds this budget")
}

print_schema_usage :: proc() {
	fmt.eprintln("usage: harbagsa-agent schema [command] [--text]")
	fmt.eprintln("")
	fmt.eprintln("Print the scenario command schema, check fields, state fields, and units.")
	fmt.eprintln("Without a command it prints one JSON object. With a command it prints")
	fmt.eprintln("that command alone. --text writes a human-readable table.")
}

cli_help :: proc(args: []string) -> int {
	if len(args) == 0 {
		print_usage()
		return EXIT_OK
	}
	if len(args) > 1 {
		fmt.eprintln("harbagsa-agent help: help takes one command")
		print_usage()
		return EXIT_SCENARIO
	}
	switch args[0] {
	case "run":
		print_run_usage()
		return EXIT_OK
	case "session":
		print_session_usage()
		return EXIT_OK
	case "diff":
		print_diff_usage()
		return EXIT_OK
	case "compare":
		print_compare_usage()
		return EXIT_OK
	case "suite":
		print_suite_usage()
		return EXIT_OK
	case "ab":
		print_ab_usage()
		return EXIT_OK
	case "schema":
		print_schema_usage()
		return EXIT_OK
	case "help":
		print_usage()
		return EXIT_OK
	}
	document := schema_build(context.allocator)
	defer schema_destroy(&document, context.allocator)
	command, found := schema_find_command(document, args[0])
	if !found {
		fmt.eprintf("harbagsa-agent help: unknown command %q\n", args[0])
		print_usage()
		return EXIT_SCENARIO
	}
	schema_print_command(command)
	return EXIT_OK
}

@(private)
print_usage :: proc() {
	fmt.eprintln("usage:")
	fmt.eprintln("  harbagsa-agent run <scenario.json|-> [options]")
	fmt.eprintln("  harbagsa-agent session [options]")
	fmt.eprintln("  harbagsa-agent diff <run-a> <run-b> [--max-pixels N] [--json]")
	fmt.eprintln("  harbagsa-agent compare <run-a> <run-b> [options]")
	fmt.eprintln("  harbagsa-agent suite <name|path> [scenario...] [options]")
	fmt.eprintln("  harbagsa-agent ab [options]")
	fmt.eprintln("  harbagsa-agent schema [command] [--text]")
	fmt.eprintln("  harbagsa-agent help [command] | -h | --help")
	fmt.eprintln("")
	fmt.eprintln("Run 'help <command>' or '<command> --help' for one command.")
	fmt.eprintln("diff pairs PNG captures by name and prints one table.")
	fmt.eprintln("compare writes a labeled before/after panel and compare.json.")
	fmt.eprintln("suite runs a manifest from suites/<name>.json in order and writes suite.json.")
}

