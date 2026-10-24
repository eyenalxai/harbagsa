#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"

MAX_SCENARIO_FRAMES :: 10_000_000

Scenario :: struct {
	commands: [dynamic]Command,
	analysis: Analysis_Config,
}

Step :: struct {
	frames:      int,
	forward:     f32,
	right:       f32,
	jump:        bool,
	look_dx:     f32,
	look_dy:     f32,
	has_forward: bool,
	has_right:   bool,
	has_jump:    bool,
	has_look:    bool,
}

scenario_load :: proc(path: string, allocator: mem.Allocator) -> (Scenario, string) {
	data, read_error := os.read_entire_file(path, allocator)
	if read_error != nil {
		return {}, fmt.aprintf("cannot read %s: %v", path, read_error, allocator = allocator)
	}
	defer delete(data, allocator)
	return scenario_parse(string(data), allocator)
}

scenario_parse :: proc(data: string, allocator: mem.Allocator) -> (Scenario, string) {
	value, parse_error := json.parse_string(data, .JSON, true, allocator)
	if parse_error != .None {
		return {}, fmt.aprintf("invalid JSON: %v", parse_error, allocator = allocator)
	}
	defer json.destroy_value(value, allocator)

	object, object_ok := json_object(value)
	if !object_ok {
		return {}, "scenario must be a JSON object"
	}
	if key, unknown := json_unknown_key(
		object,
		{"version", "view", "steps", "capture", "checks", "commands", "renderer_debug", "analysis"},
	); unknown {
		return {}, fmt.aprintf("unknown scenario key %q", key, allocator = allocator)
	}

	scenario: Scenario
	scenario.analysis = analysis_config_default()
	scenario.commands = make([dynamic]Command, 0, 16, allocator)
	ok := false
	defer if !ok {
		scenario_destroy(&scenario, allocator)
	}

	if version_value, has_version := json_get(object, "version"); has_version {
		version, version_ok := json_integer(version_value)
		if !version_ok || version != 1 {
			return {}, "scenario 'version' must be 1"
		}
	}

	if view_value, has_view := json_get(object, "view"); has_view {
		view, view_error := scenario_view(view_value)
		if view_error != "" {
			return {}, view_error
		}
		append(&scenario.commands, Command{kind = .View, view = view})
	}

	if debug_value, has_debug := json_get(object, "renderer_debug"); has_debug {
		if debug_error := scenario_renderer_debug(&scenario, debug_value); debug_error != "" {
			return {}, debug_error
		}
	}

	if analysis_value, has_analysis := json_get(object, "analysis"); has_analysis {
		config, analysis_error := scenario_analysis(analysis_value)
		if analysis_error != "" {
			return {}, analysis_error
		}
		scenario.analysis = config
	}

	has_body := false
	if steps_value, has := json_get(object, "steps"); has {
		if steps_error := scenario_steps(&scenario, object, steps_value, allocator); steps_error != "" {
			return {}, steps_error
		}
		has_body = true
	}
	if commands_value, has := json_get(object, "commands"); has {
		if has_body {
			return {}, "scenario cannot have both 'steps' and 'commands'"
		}
		if commands_error := scenario_commands(&scenario, commands_value, allocator); commands_error != "" {
			return {}, commands_error
		}
		has_body = true
	}
	if !has_body {
		return {}, "scenario needs 'steps' or 'commands'"
	}

	if checks_value, has := json_get(object, "checks"); has {
		if checks_error := scenario_add_checks(&scenario, checks_value, allocator); checks_error != "" {
			return {}, checks_error
		}
	}

	ok = true
	return scenario, ""
}

scenario_destroy :: proc(scenario: ^Scenario, allocator: mem.Allocator) {
	for &command in scenario.commands {
		command_destroy(&command, allocator)
	}
	delete(scenario.commands)
	scenario.commands = nil
}

@(private)
scenario_steps :: proc(
	scenario: ^Scenario,
	object: json.Object,
	value: json.Value,
	allocator: mem.Allocator,
) -> string {
	array, array_ok := json_array(value)
	if !array_ok || len(array) == 0 {
		return "scenario 'steps' must be a non-empty array"
	}
	steps := make([dynamic]Step, 0, len(array), allocator)
	defer delete(steps)
	total: i64
	for step_value, index in array {
		step, step_error := scenario_step(step_value)
		if step_error != "" {
			error := fmt.aprintf("step %d: %s", index, step_error, allocator = context.allocator)
			delete(step_error, context.allocator)
			return error
		}
		total += i64(step.frames)
		if total > MAX_SCENARIO_FRAMES {
			return fmt.aprintf(
				"scenario exceeds %d frames",
				MAX_SCENARIO_FRAMES,
				allocator = context.allocator,
			)
		}
		append(&steps, step)
	}

	captures, capture_error := scenario_capture_frames(object, int(total), allocator)
	if capture_error != "" {
		return capture_error
	}
	defer delete(captures, allocator)
	for frame in captures {
		append(
			&scenario.commands,
			Command {
				kind = .Capture,
				capture = {name = capture_name(frame, allocator), frame = frame, has_frame = true, alpha = 1.0},
			},
		)
	}

	for step in steps {
		if step.has_look {
			append(
				&scenario.commands,
				Command{kind = .Look, look = {dx = step.look_dx, dy = step.look_dy}},
			)
		}
		if step.has_forward || step.has_right || step.has_jump {
			append(
				&scenario.commands,
				Command {
					kind = .Input,
					input = {
						forward = step.forward,
						right = step.right,
						jump = step.jump,
						has_forward = step.has_forward,
						has_right = step.has_right,
						has_jump = step.has_jump,
					},
				},
			)
		}
		append(&scenario.commands, Command{kind = .Step, step = {frames = step.frames}})
	}

	return ""
}

capture_name :: proc(frame: int, allocator: mem.Allocator) -> string {
	return fmt.aprintf("frame_%04d", frame, allocator = allocator)
}
