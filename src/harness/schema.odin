#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:strings"

schema_build :: proc(allocator: mem.Allocator) -> Schema_Document {
	commands := make([]Schema_Command, len(COMMANDS), allocator)
	for row, index in COMMANDS {
		commands[index] = {
			name        = strings.clone(row.name, allocator),
			description = strings.clone(schema_command_description(row.kind), allocator),
			backend     = strings.clone(schema_backend_name(row.backend), allocator),
			fields      = schema_command_fields(&COMMANDS[index], allocator),
		}
	}
	return {
		version             = 1,
		commands            = commands,
		scenario_keys       = schema_clone_strings(SCENARIO_KEYS, allocator),
		suite_keys          = schema_clone_strings(SUITE_KEYS, allocator),
		suite_entry_keys    = schema_clone_strings(SUITE_ENTRY_KEYS, allocator),
		capture_targets     = schema_clone_strings(CAPTURE_TARGETS, allocator),
		capture_formats     = schema_clone_strings(CAPTURE_FORMATS, allocator),
		check_operators     = schema_clone_strings(CHECK_OPERATORS, allocator),
		check_fields        = schema_check_fields(allocator),
		state_fields        = schema_state_paths(allocator),
		units               = make([]Schema_Unit, len(SCHEMA_UNITS), allocator),
	}
}

@(private)
schema_clone_strings :: proc(values: []string, allocator: mem.Allocator) -> []string {
	clones := make([]string, len(values), allocator)
	for value, index in values {
		clones[index] = strings.clone(value, allocator)
	}
	return clones
}

schema_destroy :: proc(document: ^Schema_Document, allocator: mem.Allocator) {
	for &command in document.commands {
		delete(command.name, allocator)
		delete(command.description, allocator)
		delete(command.backend, allocator)
		for &field in command.fields {
			delete(field.name, allocator)
			delete(field.type, allocator)
		}
		delete(command.fields, allocator)
	}
	delete(document.commands, allocator)
	schema_destroy_strings(document.scenario_keys, allocator)
	schema_destroy_strings(document.suite_keys, allocator)
	schema_destroy_strings(document.suite_entry_keys, allocator)
	schema_destroy_strings(document.capture_targets, allocator)
	schema_destroy_strings(document.capture_formats, allocator)
	schema_destroy_strings(document.check_operators, allocator)
	schema_destroy_strings(document.check_fields, allocator)
	schema_destroy_strings(document.state_fields, allocator)
	delete(document.units, allocator)
	document^ = {}
}

@(private)
schema_destroy_strings :: proc(values: []string, allocator: mem.Allocator) {
	for value in values {
		delete(value, allocator)
	}
	delete(values, allocator)
}

schema_find_command :: proc(document: Schema_Document, name: string) -> (^Schema_Command, bool) {
	for &command in document.commands {
		if command.name == name {
			return &command, true
		}
	}
	return nil, false
}

cli_schema :: proc(args: []string) -> int {
	selector := ""
	text := false
	index := 0
	for index < len(args) {
		argument := args[index]
		switch {
		case argument == "--help" || argument == "-h":
			print_schema_usage()
			return EXIT_OK
		case argument == "--text":
			text = true
			index += 1
		case strings.has_prefix(argument, "-"):
			fmt.eprintf("harbagsa-agent schema: unknown option %q\n", argument)
			print_schema_usage()
			return EXIT_SCENARIO
		case selector == "":
			selector = argument
			index += 1
		case:
			fmt.eprintln("harbagsa-agent schema: schema takes one command name")
			print_schema_usage()
			return EXIT_SCENARIO
		}
	}

	document := schema_build(context.allocator)
	defer schema_destroy(&document, context.allocator)
	if selector != "" {
		command, found := schema_find_command(document, selector)
		if !found {
			fmt.eprintf("harbagsa-agent schema: unknown command %q\n", selector)
			return EXIT_SCENARIO
		}
		if text {
			schema_print_command(command)
		} else {
			schema_print_json(command^)
		}
		return EXIT_OK
	}
	if text {
		schema_print_text(document)
	} else {
		schema_print_json(document)
	}
	return EXIT_OK
}

@(private)
schema_print_json :: proc(value: any) {
	data, error := json.marshal(value, {}, context.allocator)
	if error != nil {
		fmt.eprintln("harbagsa-agent schema: cannot encode the schema")
		return
	}
	defer delete(data, context.allocator)
	fmt.println(string(data))
}

@(private)
schema_print_command :: proc(command: ^Schema_Command) {
	fmt.printf("command %s: %s\n", command.name, command.description)
	fmt.printf("backend: %s\n", command.backend)
	for field in command.fields {
		unit := field.unit == "" ? "" : fmt.aprintf(" [%s]", field.unit, allocator = context.temp_allocator)
		fmt.printf("  %-24s %-16s%s\n", field.name, field.type, unit)
	}
}

@(private)
schema_print_text :: proc(document: Schema_Document) {
	fmt.printf("schema v%d: %d commands\n\n", document.version, len(document.commands))
	fmt.printf("%-18s %-9s %s\n", "COMMAND", "BACKEND", "FIELDS")
	for command in document.commands {
		fmt.printf("%-18s %-9s %d\n", command.name, command.backend, len(command.fields))
	}
	fmt.printf("\ncheck fields: %d\n", len(document.check_fields))
	fmt.printf("state fields: %d\n", len(document.state_fields))
	fmt.printf("capture targets: %s\n", strings.join(document.capture_targets, ", ", context.temp_allocator))
	fmt.printf("capture formats: %s\n", strings.join(document.capture_formats, ", ", context.temp_allocator))
	fmt.printf("check operators: %s\n", strings.join(document.check_operators, ", ", context.temp_allocator))
}
