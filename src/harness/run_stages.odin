#+vet explicit-allocators
package harness

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

Run_Stage :: enum {
	Prepare,
	Execute,
	Collect,
	Publish,
	Swap,
}

Stage_Result :: struct {
	stage:     Run_Stage,
	exit_code: int,
	error:     string, // owned; "" is success
}

// What one run hands from stage to stage. `run_scenario` owns the state, so
// every handle the prepare stage opens closes on one path, failed or not.
Run_State :: struct {
	options:  Run_Options,
	scenario: ^Scenario,
	out_dir:  string,

	run_dir:    string,
	staging:    string,
	frames_dir: string,
	log_path:   string,
	logger:     log.Logger,
	old_logger: log.Logger,
	has_logger: bool,

	session:     Session,
	has_session: bool,
	backend:     Backend,
	run_backend: Run_Backend,

	backend_error: string,
	// The report names the first failure of the run. The stage result owns the
	// text.
	failure: string,

	state: State,
	setup: Setup_State,

	analysis_path:   string,
	analysis_failed: bool,
	trace_failed:    bool,
	trace_path:      string,
	report:          Report,
}

@(private)
failed_result :: proc(message: string, exit_code: int) -> Run_Result {
	return {
		exit_code = exit_code,
		summary = {
			ok = false,
			exit_code = exit_code,
			error = strings.clone(message, context.allocator),
		},
	}
}

// The report names one error, so a stage keeps its first failure.
@(private)
fail_stage :: proc(state: ^Run_State, result: ^Stage_Result, error: string) {
	if result.error != "" {
		delete(error, context.allocator)
		return
	}
	result.error = error
	if state.failure == "" {
		state.failure = error
	}
}

@(private)
run_prepare :: proc(state: ^Run_State) -> Stage_Result {
	if state.scenario.has_size {
		if state.options.has_size {
			return {
				stage = .Prepare,
				exit_code = EXIT_SCENARIO,
				error = format_error(
					"the scenario declares 'size', so run --size cannot override it",
				),
			}
		}
		state.options.width = state.scenario.size[0]
		state.options.height = state.scenario.size[1]
	}
	if state.options.debug_override_count > 0 {
		command, command_error := build_renderer_debug_command(state.options.common, context.allocator)
		if command_error != "" {
			return {stage = .Prepare, exit_code = EXIT_SCENARIO, error = command_error}
		}
		inject_command(state.scenario, command)
	}

	target_dir := state.out_dir
	owned_out := false
	if target_dir == "" {
		target_dir, owned_out = run_output_dir(
			state.options.scenario,
			state.options.out_dir,
			state.options.tag,
			context.allocator,
		)
	}
	absolute_out, abs_error := absolute_path(target_dir, context.allocator)
	if owned_out {
		delete(target_dir, context.allocator)
	}
	if abs_error != nil {
		return {
			stage = .Prepare,
			exit_code = EXIT_SCENARIO,
			error = format_error("cannot resolve the output directory"),
		}
	}
	state.run_dir = absolute_out

	state.staging = fmt.aprintf("%s.staging", state.run_dir, allocator = context.allocator)
	_ = os.remove_all(state.staging)
	if mkdir_error := os.make_directory_all(state.staging); mkdir_error != nil {
		return {
			stage = .Prepare,
			exit_code = EXIT_SCENARIO,
			error = format_error("cannot create the run directory"),
		}
	}
	state.frames_dir = join_path({state.staging, "frames"}, context.allocator)
	_ = os.make_directory_all(state.frames_dir)

	state.log_path = join_path({state.staging, "run.log"}, context.allocator)
	log_file, log_error := os.create(state.log_path)
	if log_error != nil {
		return {
			stage = .Prepare,
			exit_code = EXIT_SCENARIO,
			error = format_error("cannot create run.log"),
		}
	}
	logger := log.create_file_logger(
		log_file,
		lowest = .Debug,
		allocator = context.allocator,
	)
	state.old_logger = context.logger
	state.logger = logger
	context.logger = logger
	state.has_logger = true

	session, session_error := session_create(context.allocator)
	if session_error != "" {
		return {stage = .Prepare, exit_code = EXIT_RENDER, error = session_error}
	}
	state.session = session
	state.has_session = true
	// The repro path is a run side effect; the staging directory owns it and
	// moves with the run.
	state.session.output_dir = state.staging
	state.session.debug_renderer =
		state.options.debug_renderer || state.scenario.requires.renderer_debug
	session_set_timeout(&state.session, state.options.timeout_seconds)
	state.session.analysis.config = state.scenario.analysis
	if state.options.no_analysis {
		state.session.analysis.config.enabled = false
	}

	render_enabled := !state.options.no_render
	state.session.render.enabled = render_enabled
	state.run_backend = {
		width      = state.options.width,
		height     = state.options.height,
		present    = state.options.present,
		frames_dir = state.frames_dir,
		backend    = &state.backend,
		session    = &state.session,
	}
	state.session.render.provider = {ctx = &state.run_backend, ensure = run_backend_ensure}
	if state.options.present && render_enabled {
		state.backend_error = run_backend_ensure(&state.run_backend)
	}
	return {stage = .Prepare}
}

@(private)
run_execute :: proc(state: ^Run_State) -> Stage_Result {
	log.infof("harness: %d commands", len(state.scenario.commands))
	failure := execute_commands(&state.session, state.scenario^)
	result := Stage_Result{stage = .Execute}
	if failure != "" {
		session_failure(&state.session, failure)
		result.exit_code = EXIT_CHECK
		fail_stage(state, &result, failure)
	}
	return result
}

@(private)
run_collect :: proc(state: ^Run_State) -> Stage_Result {
	result := Stage_Result{stage = .Collect}
	if state.backend_error != "" {
		result.exit_code = EXIT_RENDER
	}
	if state.session.render.failed {
		result.exit_code = EXIT_RENDER
	}
	if len(state.session.perf.traces) > 0 {
		if trace_error := write_session_traces(&state.session, state.staging); trace_error != "" {
			state.trace_failed = true
			result.exit_code = EXIT_RENDER
			if state.failure == "" {
				session_failure(&state.session, trace_error)
			}
			fail_stage(state, &result, trace_error)
		}
	}
	final_frames_dir := join_path({state.run_dir, "frames"}, context.allocator)
	defer delete(final_frames_dir, context.allocator)
	analysis_path, analysis_error := write_analysis(
		state.staging,
		state.frames_dir,
		state.run_dir,
		final_frames_dir,
		state.session.capture.captures[:],
		state.session.analysis.config,
		context.allocator,
	)
	state.analysis_path = analysis_path
	if analysis_error != "" {
		state.analysis_failed = true
		result.exit_code = EXIT_RENDER
		fail_stage(state, &result, analysis_error)
	}
	state.state = session_state(&state.session)
	state_path := join_path({state.staging, "state.json"}, context.allocator)
	defer delete(state_path, context.allocator)
	if write_error := write_json_file(state_path, state.state); write_error != "" {
		result.exit_code = EXIT_RENDER
		fail_stage(state, &result, write_error)
	}

	rewrite_capture_paths(&state.session, state.run_dir)
	state.setup = setup_build(
		state.options.common,
		state.session.view,
		state.backend,
		state.session.debug_renderer,
	)
	if len(state.session.failures) > 0 {
		result.exit_code = max(result.exit_code, EXIT_CHECK)
	}
	return result
}

@(private)
run_publish :: proc(state: ^Run_State, results: []Stage_Result) -> Stage_Result {
	report := Report {
		scenario    = state.scenario.source,
		run_dir     = state.run_dir,
		frame       = state.state.frame,
		state       = state.state,
		setup       = state.setup,
		captures = state.session.capture.captures[:],
		checks      = state.session.checks[:],
		failures    = state.session.failures[:],
		digest      = state.state.digest,
		error       = state.backend_error,
	}
	if len(state.session.perf.reports) > 0 {
		report.perf = state.session.perf.reports[:]
	}
	if state.session.perf.has_trace && !state.trace_failed {
		state.trace_path = perf_trace_path(
			state.session.perf.trace_name,
			state.run_dir,
			context.allocator,
		)
		report.trace = state.trace_path
	}
	if state.analysis_path != "" && !state.analysis_failed {
		report.analysis = state.analysis_path
	}
	if len(state.session.references) > 0 {
		report.references = state.session.references[:]
	}
	exit_code := run_exit_code(results)
	report.ok = exit_code == EXIT_OK
	report.exit_code = exit_code
	if state.failure != "" && report.error == "" {
		report.error = state.failure
	}
	report_path := join_path({state.staging, "report.json"}, context.allocator)
	defer delete(report_path, context.allocator)
	result := Stage_Result{stage = .Publish}
	if write_error := write_json_file(report_path, report); write_error != "" {
		log.errorf("harness: %s", write_error)
		result.exit_code = EXIT_RENDER
		result.error = write_error
		report.ok = false
		report.exit_code = EXIT_RENDER
		report.error = write_error
	}
	state.report = report
	return result
}

@(private)
run_swap :: proc(state: ^Run_State) -> Stage_Result {
	if swap_error := swap_run_dir(state.run_dir, state.staging); swap_error != "" {
		return {stage = .Swap, exit_code = EXIT_RENDER, error = swap_error}
	}
	return {stage = .Swap}
}

@(private)
stage_results_destroy :: proc(results: ^[dynamic]Stage_Result) {
	for result in results^ {
		if result.error != "" {
			delete(result.error, context.allocator)
		}
	}
	delete(results^)
}

@(private)
run_state_destroy :: proc(state: ^Run_State) {
	state_destroy(&state.state, context.allocator)
	if state.backend.ready {
		backend_destroy(&state.backend)
	}
	if state.has_session {
		session_destroy(&state.session)
	}
	if state.has_logger {
		context.logger = state.old_logger
		log.destroy_file_logger(state.logger, allocator = context.allocator)
	}
	if state.backend_error != "" {
		delete(state.backend_error, context.allocator)
	}
	if state.trace_path != "" {
		delete(state.trace_path, context.allocator)
	}
	if state.analysis_path != "" {
		delete(state.analysis_path, context.allocator)
	}
	if state.log_path != "" {
		delete(state.log_path, context.allocator)
	}
	if state.frames_dir != "" {
		delete(state.frames_dir, context.allocator)
	}
	if state.staging != "" {
		delete(state.staging, context.allocator)
	}
	if state.run_dir != "" {
		delete(state.run_dir, context.allocator)
	}
}
