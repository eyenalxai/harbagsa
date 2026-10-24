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

Camera_State :: struct {
	position:   Vec_State `json:"position"`,
	yaw:        f32       `json:"yaw"`,
	pitch:      f32       `json:"pitch"`,
	fov:        f32       `json:"fov"`,
	overridden: bool      `json:"overridden"`,
}

Object_State :: struct {
	id:        u32         `json:"id"`,
	prefab:    string      `json:"prefab"`,
	body:      string      `json:"body"`,
	position:  Vec_State   `json:"position"`,
	rotation:  Quat_State  `json:"rotation"`,
	scale:     f32         `json:"scale"`,
	spawn_age: f32         `json:"spawn_age"`,
	light:     Light_State `json:"light"`,
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
	sky:                 bool   `json:"sky"`,
	ao:                  bool   `json:"ao"`,
}

Renderer_State :: struct {
	active:              bool                 `json:"active"`,
	frame_count:         u32                  `json:"frame_count"`,
	taa_enabled:         bool                 `json:"taa_enabled"`,
	jitter_index:        int                  `json:"jitter_index"`,
	history_valid:       bool                 `json:"history_valid"`,
	convergence_frames:  int                  `json:"convergence_frames"`,
	history_read:        int                  `json:"history_read"`,
	history_weight:      f32                  `json:"history_weight"`,
	reset_count:         int                  `json:"reset_count"`,
	last_reset:          string               `json:"last_reset"`,
	shadow_phase:        u32                  `json:"shadow_phase"`,
	light_count:         int                  `json:"light_count"`,
	atlas_weight:        f32                  `json:"atlas_weight"`,
	text_truncated_runs: int                  `json:"text_truncated_runs"`,
	text_font_drops:     int                  `json:"text_font_drops"`,
	debug:               Renderer_Debug_State `json:"debug"`,
}

State :: struct {
	frame:         int            `json:"frame"`,
	player:        Player_State   `json:"player"`,
	camera:        Camera_State   `json:"camera"`,
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
		debug = debug_state_build(debug, sim),
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
			scale     = game.simulation_object_scale(sim, object.id),
			spawn_age = game.simulation_object_spawn_age(sim, object.id),
			light     = light_state(object.light),
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
