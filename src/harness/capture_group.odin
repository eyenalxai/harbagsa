#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:strings"

import "src:renderer"

CAPTURE_OUTPUT_KEYS := []string {
	"name",
	"note",
	"target",
	"format",
	"png",
	"region",
	"rect",
	"profile",
	"crop",
	"histogram",
	"steps",
	"color_key",
}

@(private)
parse_captures :: proc(object: json.Object, allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "name", "frame", "alpha", "outputs"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Captures}
	top_name := ""
	if value, has := json_get(object, "name"); has {
		name, ok := json_string(value)
		if !ok || !valid_capture_name(name) {
			return {}, format_error("%s", "'name' must use only letters, digits, '-' and '_'")
		}
		top_name = name
	}
	if value, has := json_get(object, "frame"); has {
		frame, ok := json_integer(value)
		if !ok || frame < 0 {
			return {}, format_error("%s", "'frame' must be a non-negative integer")
		}
		command.captures.frame = frame
		command.captures.has_frame = true
	}
	if value, has := json_get(object, "alpha"); has {
		alpha, ok := json_number(value)
		if !ok || alpha < 0 || alpha > 1 {
			return {}, format_error("%s", "'alpha' must be a number in [0, 1]")
		}
		command.captures.alpha = f32(alpha)
		command.captures.has_alpha = true
	}
	outputs_value, has_outputs := json_get(object, "outputs")
	array, array_ok := json_array(outputs_value)
	if !has_outputs || !array_ok || len(array) == 0 {
		return {}, format_error("%s", "'outputs' must be a non-empty array")
	}
	if len(array) > 8 {
		return {}, format_error("%s", "a capture group holds at most 8 outputs")
	}
	outputs := make([]Capture_Command, len(array), allocator)
	ok := false
	defer if !ok {
		for &output in outputs {
			if output.name != "" {
				delete(output.name, allocator)
			}
			if output.note != "" {
				delete(output.note, allocator)
			}
		}
		delete(outputs, allocator)
	}
	for item, index in array {
		output_object, output_ok := json_object(item)
		if !output_ok {
			return {}, format_error("capture output %d must be an object", index)
		}
		if key, unknown := json_unknown_key(output_object, CAPTURE_OUTPUT_KEYS); unknown {
			return {}, format_error(
				"capture output %d has unknown key %q",
				index,
				key,
			)
		}
		synthetic := make(json.Object, len(output_object) + 1, context.temp_allocator)
		for key, value in output_object {
			synthetic[key] = value
		}
		synthetic["cmd"] = json.String("capture")
		if _, has := json_get(output_object, "name"); !has {
			synthetic["name"] = json.String(capture_group_name(top_name, index, len(array), output_object))
		}
		parsed, parse_error := parse_capture(synthetic, allocator)
		if parse_error != "" {
			return {}, parse_error
		}
		outputs[index] = parsed.capture
	}
	command.captures.outputs = outputs
	ok = true
	return command, ""
}

@(private)
capture_group_name :: proc(
	top_name: string,
	index, count: int,
	output: json.Object,
) -> string {
	target := renderer.Capture_Target.Color
	if value, has := json_get(output, "target"); has {
		if name, name_ok := json_string(value); name_ok {
			if parsed, parsed_ok := renderer.capture_target_parse(name); parsed_ok {
				target = parsed
			}
		}
	}
	if top_name != "" {
		if count == 1 {
			return top_name
		}
		return fmt.aprintf(
			"%s-%s-%d",
			top_name,
			renderer.capture_target_name(target),
			index,
			allocator = context.temp_allocator,
		)
	}
	return fmt.aprintf(
		"capture-%s-%d",
		renderer.capture_target_name(target),
		index,
		allocator = context.temp_allocator,
	)
}

captures_command_json :: proc(command: Captures_Command, allocator: mem.Allocator) -> string {
	builder := strings.builder_make(allocator)
	fmt.sbprint(&builder, `{"cmd": "captures"`)
	has_previous := true
	if command.has_frame {
		json_write_separator(&builder, &has_previous)
		fmt.sbprintf(&builder, `"frame": %d`, command.frame)
	}
	if command.has_alpha {
		json_write_separator(&builder, &has_previous)
		fmt.sbprintf(&builder, `"alpha": %g`, command.alpha)
	}
	json_write_separator(&builder, &has_previous)
	fmt.sbprint(&builder, `"outputs": [`)
	for output, index in command.outputs {
		if index > 0 {
			fmt.sbprint(&builder, `, `)
		}
		fmt.sbprint(&builder, `{`)
		output_previous := false
		capture_json_fields(&builder, output, false, &output_previous)
		fmt.sbprint(&builder, `}`)
	}
	fmt.sbprint(&builder, `]}`)
	return strings.to_string(builder)
}

