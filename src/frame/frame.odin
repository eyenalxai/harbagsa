#+vet explicit-allocators
package frame

import "core:math"

import "src:game"
import "src:geometry"
import "src:renderer"

PLAYER_FOV_X :: f32(90.0 * math.PI / 180.0)

Options :: struct {
	alpha:         f32,
	delta_seconds: f32,
	debug_view:    bool,
	captured:      bool,
	hud:           bool,
}

Scratch :: struct {
	boxes:       [game.MAX_SCENE_BOXES]geometry.Box,
	debug_lines: game.Debug_Lines,
}

Scene :: struct {
	camera:        renderer.Camera,
	sun_direction: [3]f32,
	boxes:         []geometry.Box,
	lights:        []renderer.Light,
	debug_lines:   []geometry.Line,
	hud:           renderer.HUD_Frame,
	view_flags:    renderer.View_Flags,
}

build :: proc(
	sim: ^game.Simulation,
	debug: ^game.Debug_Mode,
	options: Options,
	camera_override: ^renderer.Camera,
	hud: ^game.HUD_State,
	scratch: ^Scratch,
) -> Scene {
	scene: Scene
	scene.hud.weight = sim.settings.type_weight
	scene.sun_direction = game.debug_mode_sun_direction(debug)
	scene.sun_angular_diameter = debug.sun_angular_diameter

	box_count := 0
	for box in game.arena_static_boxes() {
		if !push_scene_box(scratch, &box_count, box) {
			break
		}
	}
	for object in game.simulation_objects(sim) {
		box := game.simulation_object_box(sim, object.id)
		if !push_scene_box(scratch, &box_count, box) {
			break
		}
	}
	scene.boxes = scratch.boxes[:box_count]

	scratch.debug_lines.count = 0
	if options.debug_view {
		game.collect_world_lines(sim, &scratch.debug_lines)
	}
	if debug.active {
		game.collect_editor_lines(debug, sim, &scratch.debug_lines)
	}
	scene.debug_lines = scratch.debug_lines.lines[:scratch.debug_lines.count]

	snapshot := game.simulation_snapshot(sim)
	scene.camera = snapshot_camera(snapshot, options.alpha)
	if camera_override != nil {
		scene.camera = camera_override^
	} else if debug.active {
		scene.camera = renderer.Camera {
			position = debug.camera.position,
			yaw      = debug.camera.yaw,
			pitch    = debug.camera.pitch,
			fov_x    = PLAYER_FOV_X,
		}
	}

	if options.hud || hud.menu.open {
		game.hud_state_update(hud, sim, debug, snapshot, options.captured)
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
	scene: Scene,
	capture := renderer.Frame_Capture{},
) -> renderer.Frame_Status {
	frame, begin_status := renderer.begin_frame(state, frame_view(scene), capture)
	if begin_status != .Ok {
		return begin_status
	}
	return renderer.end_frame(state, frame)
}

frame_view :: proc(scene: Scene) -> renderer.Frame_View {
	return {
		camera          = scene.camera,
		light_direction = scene.sun_direction,
		boxes           = scene.boxes,
		lights          = scene.lights,
		debug_lines     = scene.debug_lines,
		hud             = scene.hud,
		view_flags      = scene.view_flags,
	}
}

@(private)
push_scene_box :: proc(scratch: ^Scratch, count: ^int, box: geometry.Box) -> bool {
	if count^ >= len(scratch.boxes) {
		return false
	}
	scratch.boxes[count^] = box
	count^ += 1
	return true
}

@(private)
snapshot_camera :: proc(snapshot: game.Render_Snapshot, alpha: f32) -> renderer.Camera {
	weight := clamp(alpha, 0, 1)
	eye := snapshot.previous_eye_position +
	       (snapshot.eye_position - snapshot.previous_eye_position) * weight
	return {
		position = eye,
		yaw      = snapshot.yaw,
		pitch    = snapshot.pitch,
		fov_x    = PLAYER_FOV_X,
	}
}
