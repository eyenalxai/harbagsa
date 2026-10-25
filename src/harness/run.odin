#+vet explicit-allocators
package harness

import "core:fmt"
import "core:log"
import "core:os"

EXIT_OK :: 0
EXIT_CHECK :: 1
EXIT_SCENARIO :: 2
EXIT_RENDER :: 3

Run_Backend :: struct {
	width:     u32,
	height:    u32,
	present:   bool,
	frames_dir: string,
	backend:   ^Backend,
	session:   ^Session,
}

run_backend_ensure :: proc(ctx: rawptr) -> string {
	run := cast(^Run_Backend)ctx
	if run.backend.ready {
		return ""
	}
	created, create_error := backend_create(
		run.width,
		run.height,
		run.present,
		run.frames_dir,
		context.allocator,
	)
	if create_error != "" {
		log.errorf("harness: %s", create_error)
		return create_error
	}
	run.backend^ = created
	session_set_backend(run.session, run.backend, run.present)
	return ""
}

run_batch :: proc(options: Run_Options) -> int {
	scenario, load_error := scenario_load(options.scenario, context.allocator)
	if load_error != "" {
		print_summary_failure(load_error, EXIT_SCENARIO)
		delete(load_error, context.allocator)
		return EXIT_SCENARIO
	}
	defer scenario_destroy(&scenario, context.allocator)

	common := options.common
	if scenario.has_size {
		if common.has_size {
			print_summary_failure(
				"the scenario declares 'size', so run --size cannot override it",
				EXIT_SCENARIO,
			)
			return EXIT_SCENARIO
		}
		common.width = scenario.size[0]
		common.height = scenario.size[1]
	}
	if common.debug_override_count > 0 {
		command, command_error := build_renderer_debug_command(common, context.allocator)
		if command_error != "" {
			print_summary_failure(command_error, EXIT_SCENARIO)
			delete(command_error, context.allocator)
			return EXIT_SCENARIO
		}
		inject_command(&scenario, command)
	}

	out_dir, owned_out := run_output_dir(options.scenario, options.out_dir, common.tag, context.allocator)
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
	session.debug_renderer = options.debug_renderer
	session.analysis_config = scenario.analysis
	if options.no_analysis {
		session.analysis_config.enabled = false
	}
	defer session_destroy(&session)

	render_enabled := !options.no_render
	session.render_enabled = render_enabled
	backend: Backend
	run_backend := Run_Backend {
		width = common.width,
		height = common.height,
		present = options.present,
		frames_dir = frames_dir,
		backend = &backend,
		session = &session,
	}
	session.backend_provider = {ctx = &run_backend, ensure = run_backend_ensure}
	backend_error := ""
	if options.present && render_enabled {
		backend_error = run_backend_ensure(&run_backend)
	}
	defer if backend.ready {
		backend_destroy(&backend)
	}

	log.infof("harness: %d commands", len(scenario.commands))
	failure := execute_commands(&session, scenario)
	if failure != "" {
		session_failure(&session, failure)
	}
	trace_failed := false
	if len(session.traces) > 0 {
		if trace_error := write_session_traces(&session, staging); trace_error != "" {
			trace_failed = true
			if failure == "" {
				failure = trace_error
				session_failure(&session, failure)
			}
		}
	}
	final_frames_dir := join_path({absolute_out, "frames"}, context.allocator)
	defer delete(final_frames_dir, context.allocator)
	analysis_path, analysis_error := write_analysis(
		staging,
		frames_dir,
		absolute_out,
		final_frames_dir,
		session.captures[:],
		session.analysis_config,
		context.allocator,
	)
	analysis_failed := false
	if analysis_error != "" {
		analysis_failed = true
		if failure == "" {
			failure = analysis_error
		} else {
			delete(analysis_error, context.allocator)
		}
	}
	state := session_state(&session)
	defer state_destroy(&state, context.allocator)
	state_path := join_path({staging, "state.json"}, context.allocator)
	defer delete(state_path, context.allocator)
	state_write_failed := false
	if write_error := write_json_file(state_path, state); write_error != "" {
		state_write_failed = true
		if failure == "" {
			failure = write_error
		}
	}

	rewrite_capture_paths(&session, absolute_out)
	report_path := join_path({staging, "report.json"}, context.allocator)
	defer delete(report_path, context.allocator)
	report := Report {
		scenario    = scenario.source,
		run_dir     = absolute_out,
		frame       = state.frame,
		state       = state,
		setup       = setup_build(common, session.view, backend),
		screenshots = session.captures[:],
		checks      = session.checks[:],
		failures    = session.failures[:],
		digest      = state.digest,
		error       = backend_error,
	}
	if len(session.perf_reports) > 0 {
		report.perf = session.perf_reports[:]
	}
	if session.has_trace && !trace_failed {
		report.trace = perf_trace_path(session.trace_name, absolute_out, context.allocator)
	}
	if analysis_path != "" && !analysis_failed {
		report.analysis = analysis_path
	}
	exit_code := EXIT_OK
	if len(session.failures) > 0 || failure != "" {
		exit_code = EXIT_CHECK
	}
	if backend_error != "" ||
	   session.render_failed ||
	   state_write_failed ||
	   trace_failed ||
	   analysis_failed {
		exit_code = EXIT_RENDER
	}
	report.ok = exit_code == EXIT_OK
	report.exit_code = exit_code
	if failure != "" && report.error == "" {
		report.error = failure
	}
	if write_error := write_json_file(report_path, report); write_error != "" {
		log.errorf("harness: %s", write_error)
		exit_code = EXIT_RENDER
		report.ok = false
		report.exit_code = exit_code
		report.error = write_error
	}
	if report.trace != "" {
		delete(report.trace, context.allocator)
	}
	if analysis_path != "" {
		delete(analysis_path, context.allocator)
	}

	summary := build_summary(report, absolute_out)
	defer summary_destroy(&summary)

	if swap_error := swap_run_dir(absolute_out, staging); swap_error != "" {
		print_summary_failure(swap_error, EXIT_RENDER)
		return EXIT_RENDER
	}
	if options.verbose {
		print_verbose_summary(report)
	}
	print_summary(summary)
	if failure != "" {
		delete(failure, context.allocator)
	}
	return exit_code
}
