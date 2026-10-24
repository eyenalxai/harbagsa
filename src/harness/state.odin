#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:strings"

import "src:display"
import "src:game"

Vec_State :: struct {
	x: f32 `json:"x"`,
	y: f32 `json:"y"`,
	z: f32 `json:"z"`,
}

Quat_State :: struct {
	x: f32 `json:"x"`,
	y: f32 `json:"y"`,
	z: f32 `json:"z"`,
	w: f32 `json:"w"`,
}

Player_State :: struct {
	position: Vec_State `json:"position"`,
	eye:      Vec_State `json:"eye"`,
	velocity: Vec_State `json:"velocity"`,
	yaw:      f32       `json:"yaw"`,
	pitch:    f32       `json:"pitch"`,
	grounded: bool      `json:"grounded"`,
}

Object_State :: struct {
	id:        u32        `json:"id"`,
	prefab:    string     `json:"prefab"`,
	body:      string     `json:"body"`,
	position:  Vec_State  `json:"position"`,
	rotation:  Quat_State `json:"rotation"`,
	scale:     f32        `json:"scale"`,
	spawn_age: f32        `json:"spawn_age"`,
}

Settings_State :: struct {
	window_mode:       string `json:"window_mode"`,
	display:           string `json:"display"`,
	display_index:     int    `json:"display_index"`,
	resolution:        string `json:"resolution"`,
	window_resolution: string `json:"window_resolution"`,
	sprint_mode:       string `json:"sprint_mode"`,
	crouch_mode:       string `json:"crouch_mode"`,
	prone_mode:        string `json:"prone_mode"`,
	type_weight:       f32    `json:"type_weight"`,
}

Menu_State :: struct {
	open:     bool   `json:"open"`,
	selected: int    `json:"selected"`,
	item:     string `json:"item"`,
	status:   string `json:"status"`,
	blocked:  bool   `json:"blocked"`,
}

Settle_State :: struct {
	frames:    int  `json:"frames"`,
	converged: bool `json:"converged"`,
}

Renderer_Debug_State :: struct {
	active:              bool   `json:"active"`,
	taa:                 bool   `json:"taa"`,
	jitter:              bool   `json:"jitter"`,
	history_weight:      f32    `json:"history_weight"`,
	clamp:               bool   `json:"clamp"`,
	depth_trust:         bool   `json:"depth_trust"`,
	shadow_phase_frozen: bool   `json:"shadow_phase_frozen"`,
	shadow_phase:        u32    `json:"shadow_phase"`,
	light_shadows:       bool   `json:"light_shadows"`,
	synthetic_lights:    int    `json:"synthetic_lights"`,
}

Renderer_State :: struct {
	active:             bool                 `json:"active"`,
	frame_count:        u32                  `json:"frame_count"`,
	taa_enabled:        bool                 `json:"taa_enabled"`,
	jitter_index:       int                  `json:"jitter_index"`,
	history_valid:      bool                 `json:"history_valid"`,
	convergence_frames: int                  `json:"convergence_frames"`,
	history_read:       int                  `json:"history_read"`,
	history_weight:     f32                  `json:"history_weight"`,
	reset_count:        int                  `json:"reset_count"`,
	last_reset:         string               `json:"last_reset"`,
	shadow_phase:       u32                  `json:"shadow_phase"`,
	light_count:        int                  `json:"light_count"`,
	debug:              Renderer_Debug_State `json:"debug"`,
}

State :: struct {
	frame:         int            `json:"frame"`,
	player:        Player_State   `json:"player"`,
	objects:       []Object_State `json:"objects"`,
	settings:      Settings_State `json:"settings"`,
	debug:         Debug_State    `json:"debug"`,
	sun:           Sun_State      `json:"sun"`,
	menu:          Menu_State     `json:"menu"`,
	rows:          Rows_State     `json:"rows"`,
	settle:        Settle_State   `json:"settle"`,
	renderer:      Renderer_State `json:"renderer"`,
	render_digest: string         `json:"render_digest"`,
	digest:        string         `json:"digest"`,
}

state_build :: proc(
	sim: ^game.Simulation,
	frame: int,
	hud: ^game.HUD_State,
	debug: ^game.Debug_Mode,
	camera: Camera_State,
	renderer_state: Renderer_State,
	render_digest: string,
	settle: Settle_State,
	allocator: mem.Allocator,
) -> State {
	game.hud_state_update(hud, sim, debug, game.simulation_snapshot(sim), false, game.SIMULATION_STEP)
	menu := &hud.menu
	snapshot := game.simulation_snapshot(sim)
	resolution := game.settings_effective_resolution(sim.settings, &menu.displays)
	window_resolution := sim.settings.window.resolution
	state := State {
		frame = frame,
		player = {
			position = vec_state(snapshot.position),
			eye = vec_state(snapshot.eye_position),
			velocity = vec_state(snapshot.velocity),
			yaw = snapshot.yaw,
			pitch = snapshot.pitch,
			grounded = snapshot.grounded,
		},
		camera = camera,
		settings = {
			window_mode = game.window_mode_name(sim.settings.window.mode),
			display = strings.clone(
				game.settings_display_name(sim.settings, &menu.displays),
				allocator,
			),
			display_index = display.clamp_index(
				&menu.displays,
				sim.settings.window.display,
			),
			resolution = fmt.aprintf(
				"%dx%d",
				resolution.width,
				resolution.height,
				allocator = allocator,
			),
			window_resolution = fmt.aprintf(
				"%dx%d",
				window_resolution.width,
				window_resolution.height,
				allocator = allocator,
			),
			sprint_mode = game.input_mode_name(sim.settings.sprint_mode),
			crouch_mode = game.input_mode_name(sim.settings.crouch_mode),
			prone_mode = game.input_mode_name(sim.settings.prone_mode),
			type_weight = sim.settings.type_weight,
		},
		debug = {
			active = debug.active,
			selection = game.debug_selection_name(debug.selection),
			selected_id = selected_object_id(debug, sim),
			palette = {
				open = debug.palette.open,
				selected = debug.palette.selected,
				body = game.body_mode_name(debug.palette.body_mode),
			},
			placement = {
				armed = debug.placement.armed,
				prefab = game.prefab_name(debug.placement.prefab),
				position = debug_placement_position(debug),
				height = debug.placement.height,
				yaw = debug.placement.yaw_degrees,
				snap = debug.placement.snap,
			},
		},
		sun = sun_state(debug),
		menu = {
			open = menu.open,
			selected = int(menu.selected),
			item = game.menu_selected_name(menu),
			status = menu.status,
			blocked = menu_selected_blocked(menu),
		},
		rows = rows_state_build(hud, allocator),
		settle = settle,
		renderer = renderer_state,
		render_digest = render_digest == "" ? "" : strings.clone(render_digest, allocator),
	}
	objects := game.simulation_objects(sim)
	state.objects = make([]Object_State, len(objects), allocator)
	for object, index in objects {
		box := game.simulation_object_box(sim, object.id)
		state.objects[index] = {
			id        = u32(object.id),
			prefab    = game.prefab_name(object.prefab),
			body      = game.body_mode_name(object.body_mode),
			position  = vec_state(box.center),
			rotation  = quat_state(box.rotation),
			// The pop animation lands in a later ticket; until then every object
			// reports its settled shape and spawn age.
			scale     = 1.0,
			spawn_age = 0.0,
		}
	}
	state.digest = state_digest(state, allocator)
	return state
}

state_destroy :: proc(state: ^State, allocator: mem.Allocator) {
	if state.objects != nil {
		delete(state.objects, allocator)
		state.objects = nil
	}
	rows_state_destroy(&state.rows, allocator)
	free_string(&state.settings.display, allocator)
	free_string(&state.settings.resolution, allocator)
	free_string(&state.settings.window_resolution, allocator)
	free_string(&state.render_digest, allocator)
	free_string(&state.digest, allocator)
}

@(private)
free_string :: proc(text: ^string, allocator: mem.Allocator) {
	if text^ != "" {
		delete(text^, allocator)
		text^ = ""
	}
}

state_digest :: proc(state: State, allocator: mem.Allocator) -> string {
	hash := digest.fnv()
	digest.write_i64(&hash, i64(state.frame))
	digest.write_f32(&hash, state.player.position.x)
	digest.write_f32(&hash, state.player.position.y)
	digest.write_f32(&hash, state.player.position.z)
	digest.write_f32(&hash, state.player.eye.x)
	digest.write_f32(&hash, state.player.eye.y)
	digest.write_f32(&hash, state.player.eye.z)
	digest.write_f32(&hash, state.player.velocity.x)
	digest.write_f32(&hash, state.player.velocity.y)
	digest.write_f32(&hash, state.player.velocity.z)
	digest.write_f32(&hash, state.player.yaw)
	digest.write_f32(&hash, state.player.pitch)
	digest.write_bool(&hash, state.player.grounded)
	digest.write_string(&hash, state.settings.window_mode)
	digest.write_string(&hash, state.settings.display)
	digest.write_i64(&hash, i64(state.settings.display_index))
	digest.write_string(&hash, state.settings.resolution)
	digest.write_string(&hash, state.settings.window_resolution)
	digest.write_string(&hash, state.settings.sprint_mode)
	digest.write_string(&hash, state.settings.crouch_mode)
	digest.write_string(&hash, state.settings.prone_mode)
	digest.write_bool(&hash, state.menu.open)
	digest.write_i64(&hash, i64(state.menu.selected))
	digest.write_i64(&hash, i64(len(state.objects)))
	for object in state.objects {
		digest.write_i64(&hash, i64(object.id))
		digest.write_string(&hash, object.prefab)
		digest.write_string(&hash, object.body)
		digest.write_f32(&hash, object.position.x)
		digest.write_f32(&hash, object.position.y)
		digest.write_f32(&hash, object.position.z)
		digest.write_f32(&hash, object.rotation.x)
		digest.write_f32(&hash, object.rotation.y)
		digest.write_f32(&hash, object.rotation.z)
		digest.write_f32(&hash, object.rotation.w)
	}
	return digest.hex(hash, allocator)
}

@(private)
vec_state :: proc(value: b3.Vec3) -> Vec_State {
	return {x = value.x, y = value.y, z = value.z}
}

@(private)
quat_state :: proc(value: [4]f32) -> Quat_State {
	return {x = value[0], y = value[1], z = value[2], w = value[3]}
}
