#+vet explicit-allocators
package frame

import "core:math"
import "core:mem"

import "src:game"
import "src:geometry"
import "src:renderer"

PLAYER_FOV_X :: f32(90.0 * math.PI / 180.0)

PROBE_SPACING :: f32(2.0)
PROBE_MIN_Y :: f32(-0.5)
PROBE_COUNT_XZ :: u32(game.ARENA_SIZE / PROBE_SPACING)
PROBE_COUNT_Y :: u32((game.ARENA_WALL_HEIGHT - PROBE_MIN_Y) / PROBE_SPACING)
PROBE_VOLUMES := [1]renderer.Probe_Volume {
	{
		min = {-game.ARENA_HALF_SIZE, PROBE_MIN_Y, -game.ARENA_HALF_SIZE},
		spacing = PROBE_SPACING,
		counts = {PROBE_COUNT_XZ, PROBE_COUNT_Y, PROBE_COUNT_XZ},
	},
}

Options :: struct {
	alpha:         f32,
	delta_seconds: f32,
	debug_view:    bool,
	captured:      bool,
	hud:           bool,
	perf:          bool,
}

Scratch :: struct {
	allocator:   mem.Allocator,
	boxes:       [dynamic]geometry.Box,
	lights:      [dynamic]renderer.Light,
	debug_lines: game.Debug_Lines,
}

scratch_destroy :: proc(scratch: ^Scratch) {
	if scratch.boxes != nil {
		delete(scratch.boxes)
	}
	if scratch.lights != nil {
		delete(scratch.lights)
	}
	scratch^ = {}
}

scratch_prepare :: proc(scratch: ^Scratch) {
	if scratch.allocator.procedure == nil {
		scratch.allocator = context.allocator
	}
	if scratch.boxes == nil {
		scratch.boxes = make([dynamic]geometry.Box, 0, 0, scratch.allocator)
	}
	if scratch.lights == nil {
		scratch.lights = make([dynamic]renderer.Light, 0, 0, scratch.allocator)
	}
}

build :: proc(
	sim: ^game.Simulation,
	debug: ^game.Debug_Mode,
	options: Options,
	camera_override: ^renderer.Camera,
	hud: ^game.HUD_State,
	scratch: ^Scratch,
) -> renderer.Render_Input {
	scene: renderer.Render_Input
	scene.hud.weight = sim.settings.type_weight
	scene.light_shadows = true
	scene.probe_volumes = PROBE_VOLUMES[:]
	scene.gi = true

	snapshot := game.simulation_snapshot(sim)
	if camera_override != nil {
		scene.camera = camera_override^
	} else if debug.active {
		scene.camera = renderer.Camera {
			position = debug.camera.position,
			yaw      = debug.camera.yaw,
			pitch    = debug.camera.pitch,
			fov_x    = PLAYER_FOV_X,
		}
	} else {
		camera := game.spider_camera(sim, options.alpha)
		scene.camera = renderer.Camera {
			position = camera.position,
			yaw      = camera.yaw,
			pitch    = camera.pitch,
			fov_x    = PLAYER_FOV_X,
		}
	}

	scratch_prepare(scratch)
	clear(&scratch.boxes)
	for box in game.arena_static_boxes() {
		append(&scratch.boxes, box)
	}
	for object in game.simulation_objects(sim) {
		box := game.simulation_object_visual_box(sim, object.id)
		append(&scratch.boxes, box)
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
	scratch.debug_lines.count = 0
	if options.debug_view {
		game.collect_world_lines(sim, &scratch.debug_lines)
	}
	if debug.active {
		game.collect_editor_lines(debug, sim, &scratch.debug_lines)
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
		)
		palette := game.debug_palette_view(sim, debug)
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
	frame, begin_status := renderer.begin_frame(state, scene, capture)
	if begin_status != .Ok {
		return begin_status
	}
	return renderer.end_frame(state, frame)
}
