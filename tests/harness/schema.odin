#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "base:runtime"
import "core:encoding/json"
import "core:reflect"
import "core:strings"
import "core:testing"

import "src:game"
import "src:harness"

collect_state_paths :: proc(t: typeid, prefix: string, paths: ^[dynamic]string) {
	ti := runtime.type_info_base(type_info_of(t))
	#partial switch info in ti.variant {
	case runtime.Type_Info_Struct:
		for field in reflect.struct_fields_zipped(t) {
			name := reflect.struct_tag_get(field.tag, "json")
			if name == "" {
				name = field.name
			}
			separator := prefix == "" ? "" : "."
			path := strings.concatenate({prefix, separator, name}, context.temp_allocator)
			if prefix == "" && name == "objects" {
				collect_state_paths(typeid_of(harness.Object_State), "objects.1", paths)
				continue
			}
			if prefix == "" && name == "static_boxes" {
				collect_state_paths(typeid_of(harness.Static_Box_State), "static_boxes.0", paths)
				continue
			}
			collect_state_paths(field.type.id, path, paths)
		}
	case runtime.Type_Info_Slice:
		path := strings.concatenate({prefix, ".0"}, context.temp_allocator)
		collect_state_paths(info.elem.id, path, paths)
	case runtime.Type_Info_Array:
		path := strings.concatenate({prefix, ".0"}, context.temp_allocator)
		collect_state_paths(info.elem.id, path, paths)
	case:
		append(paths, strings.clone(prefix, context.temp_allocator))
	}
}

schema_state :: proc() -> harness.State {
	objects := make([]harness.Object_State, 1, context.temp_allocator)
	objects[0] = {
		id = 1,
		prefab = "Crate",
		body = "dynamic",
		position = {x = 1, y = 2, z = 3},
		rotation = {w = 1},
		light = {active = true, color = "warm", intensity = 1.5, range = 8},
	}
	hud_rows := make([]harness.Row_State, 1, context.temp_allocator)
	hud_rows[0] = {kind = "metric", label = "A", value = "B", ratio = 0.5, ticks = 3}
	menu_rows := make([]harness.Row_State, 1, context.temp_allocator)
	menu_rows[0] = {kind = "setting", label = "C", value = "D"}
	static_boxes := make([]harness.Static_Box_State, 1, context.temp_allocator)
	static_boxes[0] = {
		center = {x = 0, y = 1, z = 2},
		half_extents = {x = 3, y = 4, z = 5},
		color = {r = 1, g = 0.5, b = 0.25, a = 1},
		rotation = {w = 1},
	}
	return {
		frame = 7,
		objects = objects,
		static_boxes = static_boxes,
		rows = harness.Rows_State{hud = hud_rows, menu = menu_rows},
	}
}

@(test)
every_state_field_resolves_through_the_schema :: proc(t: ^testing.T) {
	state := schema_state()
	paths := make([dynamic]string, 0, 160, context.temp_allocator)
	collect_state_paths(typeid_of(harness.State), "", &paths)
	append(&paths, "objects.count")
	append(&paths, "static_boxes.count")

	testing.expect(t, len(paths) > 100, "the schema walk found too few fields")
	for path in paths {
		_, error := harness.state_field(state, path)
		testing.expectf(t, error == "", "field %q did not resolve: %s", path, error)
		if error != "" {
			delete(error, context.allocator)
		}
	}
}

@(test)
schema_covers_every_command_and_the_new_fields :: proc(t: ^testing.T) {
	document := harness.schema_build(context.allocator)
	defer harness.schema_destroy(&document, context.allocator)
	testing.expect_value(t, len(document.commands), len(harness.COMMANDS))
	for row in harness.COMMANDS {
		command, found := harness.schema_find_command(document, row.name)
		testing.expectf(t, found, "command %q is missing from the schema", row.name)
		if found {
			testing.expect_value(t, command.name, row.name)
			testing.expect_value(t, command.description, row.description)
			testing.expectf(
				t,
				row.description != "",
				"command %q has no description",
				row.name,
			)
		}
	}
	scene, scene_found := harness.schema_find_command(document, "scene")
	testing.expect(t, scene_found, "scene is missing from the schema")
	if scene_found {
		for name in ([?]string{"camera", "sun", "objects", "settings", "view", "renderer_debug"}) {
			_, found := harness.schema_field_named(scene, name)
			testing.expectf(t, found, "scene field %q is missing", name)
		}
	}
	capture, capture_found := harness.schema_find_command(document, "capture")
	testing.expect(t, capture_found, "capture is missing from the schema")
	if capture_found {
		_, found := harness.schema_field_named(capture, "steps")
		testing.expect(t, found, "capture.steps is missing")
	}
	debug, debug_found := harness.schema_find_command(document, "renderer_debug")
	testing.expect(t, debug_found, "renderer_debug is missing from the schema")
	if debug_found {
		testing.expect(
			t,
			strings.contains(debug.description, "null"),
			"the renderer_debug schema does not name the null reset",
		)
		for name in ([?]string{"taa", "depth_trust", "gi", "ao_radius"}) {
			field, found := harness.schema_field_named(debug, name)
			testing.expectf(t, found, "renderer_debug field %q is missing from the schema", name)
			if found {
				testing.expectf(
					t,
					strings.has_suffix(field.type, "?"),
					"renderer_debug field %q is not optional: %s",
					name,
					field.type,
				)
			}
		}
	}
	testing.expect(t, schema_contains(document.check_fields, "analysis.bands.region.x"), "the band region check is missing")
	testing.expect(t, schema_contains(document.state_fields, "player.position.y"), "the state schema is missing")
}

@(private)
schema_contains :: proc(values: []string, wanted: string) -> bool {
	for value in values {
		if value == wanted {
			return true
		}
	}
	return false
}

@(test)
an_unknown_state_path_names_the_path :: proc(t: ^testing.T) {
	state := schema_state()
	_, error := harness.state_field(state, "player.nope")
	testing.expect(t, strings.contains(error, "player.nope"), "the error did not name the path")
	if error != "" {
		delete(error, context.allocator)
	}

	_, error = harness.state_field(state, "objects.1.nope")
	testing.expect(t, strings.contains(error, "objects.1.nope"), "the error did not name the object path")
	if error != "" {
		delete(error, context.allocator)
	}
}

@(test)
state_build_does_not_touch_the_menu_or_the_hud :: proc(t: ^testing.T) {
	sim := game.simulation_create(context.allocator)
	defer game.simulation_destroy(&sim)
	debug := game.debug_mode_create(context.allocator)
	defer game.debug_mode_destroy(&debug)
	hud: game.HUD_State
	game.menu_open(&hud.menu)
	hud.menu.status = "unchanged"
	hud.menu.status_remaining = 0.75

	state := harness.state_build(
		&sim,
		12,
		&hud,
		&debug,
		{},
		{last_reset = "none"},
		"",
		{},
		context.allocator,
	)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, hud.menu.status, "unchanged")
	testing.expect_value(t, hud.menu.status_remaining, f32(0.75))
	testing.expect_value(t, state.debug.sun, state.sun)
}

@(test)
reply_json_uses_the_state_tags :: proc(t: ^testing.T) {
	state := schema_state()
	reply := harness.Reply{ok = true, cmd = "state", frame = 7, state = &state}
	data := harness.encode_reply(reply)
	defer delete(data, context.allocator)

	value, parse_error := json.parse_string(string(data), .JSON, true, context.temp_allocator)
	testing.expectf(t, parse_error == .None, "reply JSON did not parse: %v", parse_error)
	root, object_ok := value.(json.Object)
	testing.expect(t, object_ok, "reply JSON is not an object")
	if !object_ok {
		return
	}
	encoded, has_state := root["state"]
	testing.expect(t, has_state, "the reply lost the state")
	state_object, state_ok := encoded.(json.Object)
	testing.expect(t, state_ok, "the state is not an object")
	if !state_ok {
		return
	}
	_, has_player := state_object["player"]
	_, has_render_digest := state_object["render_digest"]
	testing.expect(t, has_player, "the state JSON lost the player")
	testing.expect(t, has_render_digest, "the state JSON lost the render digest")
}

@(test)
state_marshals_with_the_tagged_struct :: proc(t: ^testing.T) {
	state := schema_state()
	data, marshal_error := json.marshal(state, {}, context.temp_allocator)
	testing.expectf(t, marshal_error == nil, "state marshal failed: %v", marshal_error)
	if marshal_error == nil {
		testing.expect(t, strings.contains(string(data), `"render_digest"`), "the state JSON lost a tag")
	}
}

@(test)
a_state_command_does_not_advance_the_menu_status :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	defer harness.session_destroy(&session)
	game.menu_open(&session.hud.menu)
	session.hud.menu.status = "unchanged"
	session.hud.menu.status_remaining = 0.5

	state := harness.session_state(&session)
	defer harness.state_destroy(&state, context.allocator)
	testing.expect_value(t, session.hud.menu.status_remaining, f32(0.5))
}
