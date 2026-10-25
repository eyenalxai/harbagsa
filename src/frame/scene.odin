#+vet explicit-allocators
#+vet !unused-procedures // the game key and the harness use this API
package frame

import "core:encoding/json"
import "core:math"
import "core:mem"
import "core:strings"

import "src:display"
import "src:game"
import "src:renderer"

Scene_Player :: struct {
	position:       [3]f32 `json:"position"`,
	yaw_deg:        f32    `json:"yaw_deg"`,
	pitch_deg:      f32    `json:"pitch_deg"`,
	stance:         string `json:"stance"`,
	velocity:       [3]f32 `json:"velocity"`,
	grounded:       bool   `json:"grounded"`,
	step_smoothing: f32    `json:"step_smoothing"`,
	eye_height:     f32    `json:"eye_height"`,
}

Scene_Camera :: struct {
	source:    string       `json:"source"`,
	position:  [3]f32       `json:"position"`,
	yaw_deg:   f32          `json:"yaw_deg"`,
	pitch_deg: f32          `json:"pitch_deg"`,
	fov_deg:   f32          `json:"fov_deg"`,
	player:    Maybe(Scene_Player) `json:"player,omitempty"`,
}

Scene_Sun :: struct {
	position:             [3]f32 `json:"position"`,
	angular_diameter_deg: f32    `json:"angular_diameter_deg"`,
}

Scene_Light :: struct {
	active:    bool   `json:"active"`,
	color:     string `json:"color"`,
	intensity: f32    `json:"intensity"`,
	range:     f32    `json:"range"`,
	emissive:  f32    `json:"emissive"`,
}

Scene_Object :: struct {
	id:       u32        `json:"id"`,
	prefab:   string     `json:"prefab"`,
	body:     string     `json:"body"`,
	position: [3]f32     `json:"position"`,
	rotation: [4]f32     `json:"rotation"`,
	color:    [4]f32     `json:"color"`,
	light:    Scene_Light `json:"light"`,
}

Scene_Settings :: struct {
	window_mode:  string `json:"window_mode"`,
	display:      int    `json:"display"`,
	resolution:   [2]i32 `json:"resolution"`,
	sprint_mode:  string `json:"sprint_mode"`,
	crouch_mode:  string `json:"crouch_mode"`,
	prone_mode:   string `json:"prone_mode"`,
	type_weight:  f32    `json:"type_weight"`,
}

Scene_View :: struct {
	hud:   bool `json:"hud"`,
	debug: bool `json:"debug"`,
	hint:  bool `json:"hint"`,
	perf:  bool `json:"perf"`,
}

Scene_Display :: struct {
	name:    string    `json:"name"`,
	desktop: [2]i32    `json:"desktop"`,
	modes:   [][2]i32  `json:"modes"`,
}

Scene :: struct {
	camera:   Scene_Camera   `json:"camera"`,
	sun:      Scene_Sun      `json:"sun"`,
	objects:  []Scene_Object `json:"objects"`,
	settings:       Scene_Settings       `json:"settings"`,
	view:           Scene_View           `json:"view"`,
	displays:       []Scene_Display      `json:"displays,omitempty"`,
	renderer_debug: Maybe(renderer.Renderer_Debug_Patch) `json:"renderer_debug,omitempty"`,
}

scene_capture :: proc(
	sim: ^game.Simulation,
	debug: ^game.Debug_Mode,
	view: Options,
	camera_override: ^renderer.Camera,
	renderer_debug: ^renderer.Renderer_Debug,
	allocator: mem.Allocator,
) -> Scene {
	scene := Scene {
		view = {
			hud = view.hud,
			debug = view.debug_view,
			hint = !view.captured,
			perf = view.perf,
		},
		sun = {
			position = debug.sun.position,
			angular_diameter_deg = f32(math.to_degrees(debug.sun_angular_diameter)),
		},
	}
	scene.camera.fov_deg = f32(math.to_degrees(PLAYER_FOV_X))
	if camera_override != nil {
		scene.camera.source = strings.clone("override", allocator)
		scene.camera.position = camera_override.position
		scene.camera.yaw_deg = f32(math.to_degrees(camera_override.yaw))
		scene.camera.pitch_deg = f32(math.to_degrees(camera_override.pitch))
		scene.camera.fov_deg = f32(math.to_degrees(camera_override.fov_x))
	} else if debug.active {
		scene.camera.source = strings.clone("debug", allocator)
		scene.camera.position = debug.camera.position
		scene.camera.yaw_deg = f32(math.to_degrees(debug.camera.yaw))
		scene.camera.pitch_deg = f32(math.to_degrees(debug.camera.pitch))
	} else {
		snapshot := game.simulation_snapshot(sim)
		scene.camera.source = strings.clone("player", allocator)
		scene.camera.position = snapshot.eye_position
		scene.camera.yaw_deg = f32(math.to_degrees(snapshot.yaw))
		scene.camera.pitch_deg = f32(math.to_degrees(snapshot.pitch))
		scene.camera.player = Scene_Player {
			position = snapshot.position,
			yaw_deg = f32(math.to_degrees(snapshot.yaw)),
			pitch_deg = f32(math.to_degrees(snapshot.pitch)),
			stance = strings.clone(game.stance_name(snapshot.stance), allocator),
			velocity = {snapshot.velocity.x, snapshot.velocity.y, snapshot.velocity.z},
			grounded = snapshot.grounded,
			step_smoothing = snapshot.step_smoothing,
			eye_height = sim.player.eye_height,
		}
	}

	settings := &sim.settings
	scene.settings = {
		window_mode = strings.clone(game.window_mode_name(settings.window.mode), allocator),
		display = settings.window.display,
		resolution = {i32(settings.window.resolution.width), i32(settings.window.resolution.height)},
		sprint_mode = strings.clone(game.input_mode_name(settings.sprint_mode), allocator),
		crouch_mode = strings.clone(game.input_mode_name(settings.crouch_mode), allocator),
		prone_mode = strings.clone(game.input_mode_name(settings.prone_mode), allocator),
		type_weight = settings.type_weight,
	}

	objects := game.object_snapshot_capture(sim, allocator)
	defer game.object_snapshot_destroy(&objects, allocator)
	scene.objects = make([]Scene_Object, len(objects.objects), allocator)
	for object, index in objects.objects {
		scene.objects[index] = {
			id = u32(object.id),
			prefab = strings.clone(game.prefab_name(object.prefab), allocator),
			body = strings.clone(game.body_mode_name(object.body_mode), allocator),
			position = object.center,
			rotation = {object.rotation.x, object.rotation.y, object.rotation.z, object.rotation.w},
			color = object.color,
			light = {
				active = object.light.active,
				color = strings.clone(game.light_color_name(object.light.color), allocator),
				intensity = object.light.intensity,
				range = object.light.range,
				emissive = object.light.emissive,
			},
		}
	}

	if renderer_debug != nil && renderer_debug.active {
		scene.renderer_debug = renderer.renderer_debug_patch(renderer_debug^)
	}

	displays := &sim.settings.display
	scene.displays = make([]Scene_Display, displays.count, allocator)
	for index in 0 ..< displays.count {
		info := &displays.items[index]
		modes := make([][2]i32, info.mode_count, allocator)
		for mode, mode_index in info.modes[:info.mode_count] {
			modes[mode_index] = {mode.width, mode.height}
		}
		scene.displays[index] = {
			name = strings.clone(display.name(info), allocator),
			desktop = {info.desktop.width, info.desktop.height},
			modes = modes,
		}
	}
	return scene
}

scene_destroy :: proc(scene: ^Scene, allocator: mem.Allocator) {
	delete(scene.camera.source, allocator)
	if player, has_player := scene.camera.player.?; has_player {
		delete(player.stance, allocator)
	}
	for object in scene.objects {
		delete(object.prefab, allocator)
		delete(object.body, allocator)
		delete(object.light.color, allocator)
	}
	delete(scene.objects, allocator)
	delete(scene.settings.window_mode, allocator)
	delete(scene.settings.sprint_mode, allocator)
	delete(scene.settings.crouch_mode, allocator)
	delete(scene.settings.prone_mode, allocator)
	for display_info in scene.displays {
		delete(display_info.name, allocator)
		delete(display_info.modes, allocator)
	}
	delete(scene.displays, allocator)
	scene^ = {}
}

// A scene document is one command object, so a recorded or keyed file is a
// normal scenario command.
scene_json :: proc(scene: Scene, allocator: mem.Allocator, pretty := true) -> string {
	options: json.Marshal_Options
	options.pretty = pretty
	data, marshal_error := json.marshal(scene, options, allocator)
	if marshal_error != nil {
		return ""
	}
	defer delete(data, allocator)
	builder := strings.builder_make(allocator)
	strings.write_string(&builder, `{"cmd": "scene",`)
	if len(data) > 1 {
		strings.write_string(&builder, string(data[1:]))
	} else {
		strings.write_string(&builder, "}")
	}
	return strings.to_string(builder)
}
