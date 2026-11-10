#+vet explicit-allocators
package frame

import "core:math"
import "core:mem"

import "src:bake"
import "src:game"
import "src:renderer"

PLAYER_FOV_X :: f32(90.0 * math.PI / 180.0)

Camera_View :: struct {
	source: string,
	camera: renderer.Camera,
	player: Maybe(game.Render_Snapshot),
}

Options :: struct {
	alpha:         f32,
	delta_seconds: f32,
	debug_view:    bool,
	captured:      bool,
	hud:           bool,
	perf:          bool,
	bake:          renderer.Bake_Report,
}

Scratch :: struct {
	allocator:   mem.Allocator,
	boxes:       [dynamic]renderer.Frame_Box,
	lights:      [dynamic]renderer.Light,
	bake:        game.Bake_Input,
	debug_lines: game.Debug_Lines,
}

scratch_destroy :: proc(scratch: ^Scratch) {
	if scratch.boxes != nil {
		delete(scratch.boxes)
	}
	if scratch.lights != nil {
		delete(scratch.lights)
	}
	game.bake_input_destroy(&scratch.bake)
	scratch^ = {}
}

scratch_prepare :: proc(scratch: ^Scratch) {
	if scratch.allocator.procedure == nil {
		scratch.allocator = context.allocator
	}
	if scratch.boxes == nil {
		scratch.boxes = make([dynamic]renderer.Frame_Box, 0, 0, scratch.allocator)
	}
	if scratch.lights == nil {
		scratch.lights = make([dynamic]renderer.Light, 0, 0, scratch.allocator)
	}
}

camera_view :: proc(
	sim: ^game.Simulation,
	debug: ^game.Debug_Mode,
	camera_override: ^renderer.Camera,
	alpha: f32,
) -> Camera_View {
	if camera_override != nil {
		return {source = "override", camera = camera_override^}
	}
	if debug.active {
		return {
			source = "debug",
			camera = {
				position = debug.camera.position,
				yaw = debug.camera.yaw,
				pitch = debug.camera.pitch,
				fov_x = PLAYER_FOV_X,
			},
		}
	}
	camera := game.spider_camera(sim, alpha)
	return {
		source = "third_person",
		camera = {
			position = camera.position,
			yaw = camera.yaw,
			pitch = camera.pitch,
			fov_x = PLAYER_FOV_X,
		},
		player = game.simulation_snapshot(sim),
	}
}

@(private)
build :: proc(
	sim: ^game.Simulation,
	debug: ^game.Debug_Mode,
	options: Options,
	camera_override: ^renderer.Camera,
	hud: ^game.HUD_State,
	scratch: ^Scratch,
	bake_static: bake.Static,
) -> renderer.Render_Input {
	scene: renderer.Render_Input
	scene.hud.weight = sim.settings.type_weight
	scene.light_shadows = true

	view := camera_view(sim, debug, camera_override, options.alpha)
	scene.camera = view.camera
	snapshot, has_player := view.player.?
	if !has_player {
		snapshot = game.simulation_snapshot(sim)
	}

	scratch_prepare(scratch)
	clear(&scratch.boxes)
	for box, index in game.arena_static_boxes() {
		append(&scratch.boxes, renderer.Frame_Box {
			box = box,
			slot = game.bake_arena_slot(index),
		})
	}
	for object in game.simulation_objects(sim) {
		append(&scratch.boxes, renderer.Frame_Box {
			box = game.simulation_object_visual_box(sim, object.id),
			slot = game.bake_placed_slot(object),
		})
	}
	spider_boxes(&scratch.boxes, snapshot, options.alpha)
	scene.boxes = scratch.boxes[:]

	active := game.simulation_collect_lights(sim)
	clear(&scratch.lights)
	for light in active {
		append(&scratch.lights, renderer.Light {
			position  = light.position,
			intensity = light.intensity,
			color     = light.color,
			range     = light.range,
		})
	}
	scene.lights = scratch.lights[:]
	scene.bake_static = bake_static
	scratch.debug_lines.count = 0
	if options.debug_view {
		game.collect_world_lines(sim, &scratch.debug_lines)
	}
	if debug.active {
		game.collect_editor_lines(&debug.editor, sim, debug.camera, &scratch.debug_lines)
	}
	scene.debug_lines = scratch.debug_lines.lines[:scratch.debug_lines.count]

	if options.hud || hud.menu.open {
		game.hud_state_update(
			hud,
			sim,
			debug,
			snapshot,
			options.captured,
			options.delta_seconds,
			{status = options.bake.status, key = options.bake.key},
		)
		palette := game.editor_palette_view(sim, &debug.editor, debug.active)
		if hud.menu.open {
			palette.open = false
		}
		scene.hud = renderer.HUD_Frame {
			enabled      = true,
			menu_open    = hud.menu.open,
			view         = hud.view,
			capture_hint = hud.capture_hint,
			captured     = hud.captured,
			menu         = hud.menu.view,
			palette      = palette,
			weight       = sim.settings.type_weight,
		}
	}
	if scene.hud.enabled {
		scene.view_flags |= {.HUD}
		if hud.perf.visible {
			scene.view_flags |= {.Perf}
		}
		if scene.hud.palette.open && !scene.hud.menu_open {
			scene.view_flags |= {.Palette}
		}
		if !scene.hud.captured && scene.hud.capture_hint != "" && !scene.hud.palette.open {
			scene.view_flags |= {.Capture_Hint}
		}
	}
	if scene.hud.menu_open {
		scene.view_flags |= {.Menu}
	}
	if options.debug_view {
		scene.view_flags |= {.Debug_Draw}
	}

	return scene
}

draw :: proc(
	state: ^renderer.Renderer,
	scene: renderer.Render_Input,
	capture := renderer.Frame_Capture{},
) -> renderer.Frame_Status {
	return renderer.render_frame(state, scene, capture).status
}
