#+vet explicit-allocators
package harness

import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"

EXIT_OK :: 0
EXIT_CHECK :: 1
EXIT_SCENARIO :: 2
EXIT_RENDER :: 3

Run_Options :: struct {
	scenario:  string,
	out_dir:   string,
	width:     u32,
	height:    u32,
	present:   bool,
	no_render: bool,
}

Report :: struct {
	ok:          bool             `json:"ok"`,
	exit_code:   int              `json:"exit_code"`,
	scenario:    string           `json:"scenario"`,
	run_dir:     string           `json:"run_dir"`,
	frame:       int              `json:"frame"`,
	state:       State            `json:"state"`,
	screenshots: []Capture_Result `json:"screenshots"`,
	checks:      []Check_Result   `json:"checks"`,
	failures:    []string         `json:"failures"`,
	digest:      string           `json:"digest"`,
	error:       string           `json:"error,omitempty"`,
}

Run_Summary :: struct {
	ok:          bool     `json:"ok"`,
	exit_code:   int      `json:"exit_code"`,
	run_dir:     string   `json:"run_dir"`,
	report:      string   `json:"report"`,
	state:       string   `json:"state"`,
	screenshots: []string `json:"screenshots"`,
	digest:      string   `json:"digest"`,
	error:       string   `json:"error,omitempty"`,
}

run_batch :: proc(options: Run_Options) -> int {
	scenario, load_error := scenario_load(options.scenario, context.allocator)
	if load_error != "" {
		print_summary_failure(load_error, EXIT_SCENARIO)
		return EXIT_SCENARIO
	}
	defer scenario_destroy(&scenario, context.allocator)

	out_dir := options.out_dir
	owned_out := false
	if out_dir == "" {
		stem := filepath.stem(options.scenario)
		out_dir = fmt.aprintf("runs/%s", stem, allocator = context.allocator)
		owned_out = true
	}
	absolute_out, abs_error := absolute_path(out_dir, context.allocator)
	if abs_error != nil {
		print_summary_failure("cannot resolve the output directory", EXIT_SCENARIO)
		return EXIT_SCENARIO
	}
	if owned_out {
		delete(out_dir, context.allocator)
	}
	defer delete(absolute_out, context.allocator)

	staging := fmt.aprintf("%s.staging", absolute_out, allocator = context.allocator)
	defer delete(staging, context.allocator)
	_ = os.remove_all(staging)
	if mkdir_error := os.make_directory_all(staging); mkdir_error != nil {
		print_summary_failure("cannot create the run directory", EXIT_SCENARIO)
		return EXIT_SCENARIO
	}
	frames_dir := join_path({staging, "frames"}, context.allocator)
	defer delete(frames_dir, context.allocator)
	_ = os.make_directory_all(frames_dir)

	log_path := join_path({staging, "run.log"}, context.allocator)
	defer delete(log_path, context.allocator)
	log_file, log_error := os.create(log_path)
	if log_error != nil {
		print_summary_failure("cannot create run.log", EXIT_SCENARIO)
		return EXIT_SCENARIO
	}
	logger := log.create_file_logger(
		log_file,
		lowest = .Debug,
		allocator = context.allocator,
	)
	old_logger := context.logger
	context.logger = logger
	defer {
		context.logger = old_logger
		log.destroy_file_logger(logger, allocator = context.allocator)
	}

	session, session_error := session_create(context.allocator)
	if session_error != "" {
		print_summary_failure(session_error, EXIT_RENDER)
		return EXIT_RENDER
	}
	defer session_destroy(&session)

	has_capture := scenario_has_capture(scenario)
	render_enabled := !options.no_render
	needs_backend := render_enabled && (options.present || has_capture)
	backend: Backend
	backend_error := ""
	if needs_backend {
		created, create_error := backend_create(
			options.width,
			options.height,
			options.present,
			frames_dir,
			context.allocator,
		)
		if create_error != "" {
			backend_error = create_error
			log.errorf("harness: %s", create_error)
		} else {
			backend = created
			session_set_backend(&session, &backend, options.present)
		}
	}
	defer if backend.ready {
		backend_destroy(&backend)
	}

	failure := ""
	for command in scenario.commands {
		log.infof("harness: %s at frame %d", command_name(command.kind), session.frame)
		if command.kind == .Capture && (!render_enabled || !backend.ready) {
			log.warn("harness: capture skipped because rendering is disabled")
			continue
		}
		reply := session_execute(&session, command, "")
		ok := reply.ok
		if !ok && failure == "" {
			failure = strings.clone(reply.error, context.allocator)
		}
		reply_destroy(&reply, context.allocator)
		if !ok || session.quit {
			break
		}
	}

	if failure != "" {
		session_failure(&session, failure)
	}
	state := session_state(&session)
	defer state_destroy(&state, context.allocator)
	state_path := join_path({staging, "state.json"}, context.allocator)
	defer delete(state_path, context.allocator)
	if write_error := write_json_file(state_path, state); write_error != "" {
		if failure == "" {
			failure = write_error
		}
	}

	rewrite_capture_paths(&session, absolute_out)
	report_path := join_path({staging, "report.json"}, context.allocator)
	defer delete(report_path, context.allocator)
	report := Report {
		scenario    = options.scenario,
		run_dir     = absolute_out,
		frame       = state.frame,
		state       = state,
		screenshots = session.captures[:],
		checks      = session.checks[:],
		failures    = session.failures[:],
		digest      = state.digest,
		error       = backend_error,
	}
	exit_code := EXIT_OK
	if len(session.failures) > 0 || failure != "" {
		exit_code = EXIT_CHECK
	}
	if backend_error != "" {
		exit_code = EXIT_RENDER
	}
	report.ok = exit_code == EXIT_OK
	report.exit_code = exit_code
	if failure != "" && report.error == "" {
		report.error = failure
	}
	if write_error := write_json_file(report_path, report); write_error != "" {
		log.errorf("harness: %s", write_error)
	}

	summary := build_summary(report, absolute_out)
	defer summary_destroy(&summary)

	if swap_error := swap_run_dir(absolute_out, staging); swap_error != "" {
		print_summary_failure(swap_error, EXIT_RENDER)
		return EXIT_RENDER
	}
	print_summary(summary)
	if failure != "" {
		delete(failure, context.allocator)
	}
	return exit_code
}

scenario_has_capture :: proc(scenario: Scenario) -> bool {
	for command in scenario.commands {
		if command.kind == .Capture {
			return true
		}
	}
	return false
}

@(private)
rewrite_capture_paths :: proc(session: ^Session, out_dir: string) {
	for &capture in session.captures {
		filename := fmt.aprintf("%s.png", capture.name, allocator = context.temp_allocator)
		final_path := join_path({out_dir, "frames", filename}, context.allocator)
		if final_path == "" {
			continue
		}
		if capture.path != "" {
			delete(capture.path, context.allocator)
		}
		capture.path = final_path
	}
}
