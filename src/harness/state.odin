#+vet explicit-allocators
package harness

import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"

import "src:display"
import "src:game"
import "src:renderer"

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
	yaw_deg:  f32       `json:"yaw_deg"`,
	pitch_deg: f32      `json:"pitch_deg"`,
	grounded: bool      `json:"grounded"`,
}

Camera_State :: struct {
	position:   Vec_State `json:"position"`,
	yaw_deg:    f32       `json:"yaw_deg"`,
	pitch_deg:  f32       `json:"pitch_deg"`,
	fov_deg:    f32       `json:"fov_deg"`,
	source:     string    `json:"source"`,
	overridden: bool      `json:"overridden"`,
}

Object_State :: struct {
	id:        u32         `json:"id"`,
	prefab:    string      `json:"prefab"`,
	body:      string      `json:"body"`,
	position:  Vec_State   `json:"position"`,
	rotation:  Quat_State  `json:"rotation"`,
	scale:     f32         `json:"scale" digest:"-"`,
	spawn_age: f32         `json:"spawn_age" digest:"-"`,
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
	item:     string `json:"item" digest:"-"`,
	status:   string `json:"status" digest:"-"`,
	blocked:  bool   `json:"blocked" digest:"-"`,
}

Settle_State :: struct {
	frames:    int  `json:"frames"`,
	converged: bool `json:"converged"`,
}

State :: struct {
	frame:         int            `json:"frame"`,
	player:        Player_State   `json:"player"`,
	camera:        Camera_State   `json:"camera" digest:"-"`,
	objects:       []Object_State `json:"objects"`,
	settings:      Settings_State `json:"settings"`,
	debug:         Debug_State    `json:"debug" digest:"-"`,
	sun:           Sun_State      `json:"sun"`,
	menu:          Menu_State     `json:"menu"`,
	rows:          Rows_State     `json:"rows" digest:"-"`,
	settle:        Settle_State   `json:"settle" digest:"-"`,
	renderer:      renderer.Renderer_Report `json:"renderer" digest:"-"`,
	render_digest: string         `json:"render_digest" digest:"-"`,
	digest:        string         `json:"digest" digest:"-"`,
}

State_Section :: enum {
	Frame,
	Player,
	Camera,
	Objects,
	Settings,
	Debug,
	Menu,
	Rows,
	Settle,
	Renderer,
	Render_Digest,
}

State_Sections :: bit_set[State_Section]

ALL_STATE_SECTIONS :: State_Sections {
	.Frame,
	.Player,
	.Camera,
	.Objects,
	.Settings,
	.Debug,
	.Menu,
	.Rows,
	.Settle,
	.Renderer,
	.Render_Digest,
}

state_build :: proc(
	sim: ^game.Simulation,
	frame: int,
	hud: ^game.HUD_State,
	debug: ^game.Debug_Mode,
	camera: Camera_State,
	renderer_state: renderer.Renderer_Report,
	render_digest: string,
	settle: Settle_State,
	allocator: mem.Allocator,
) -> State {
	return state_build_sections(
		sim,
		frame,
		hud,
		debug,
		camera,
		renderer_state,
		render_digest,
		settle,
		ALL_STATE_SECTIONS,
		allocator,
	)
}

// A check names one namespace, so the command builds only that namespace. The
// digest needs every section; every other check is a partial document.
state_build_sections :: proc(
	sim: ^game.Simulation,
	frame: int,
	hud: ^game.HUD_State,
	debug: ^game.Debug_Mode,
	camera: Camera_State,
	renderer_state: renderer.Renderer_Report,
	render_digest: string,
	settle: Settle_State,
	sections: State_Sections,
	allocator: mem.Allocator,
) -> State {
	menu := &hud.menu
	state := State {
		frame = frame,
		camera = camera,
		settle = settle,
		renderer = renderer_state,
	}

	if .Player in sections {
		snapshot := game.simulation_snapshot(sim)
		state.player = {
			position = vec_state(snapshot.position),
			eye = vec_state(snapshot.eye_position),
			velocity = vec_state(snapshot.velocity),
			yaw_deg = f32(math.to_degrees(snapshot.yaw)),
			pitch_deg = f32(math.to_degrees(snapshot.pitch)),
			grounded = snapshot.grounded,
		}
	}
	if .Objects in sections {
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
	}
	if .Settings in sections {
		resolution := game.settings_effective_resolution(sim.settings, &menu.displays)
		window_resolution := sim.settings.window.resolution
		state.settings = {
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
		}
	}
	if .Debug in sections {
		sun := sun_state(debug)
		state.sun = sun
		state.debug = debug_state_build(debug, sim, sun)
	}
	if .Menu in sections {
		state.menu = {
			open = menu.open,
			selected = int(menu.selected),
			item = game.menu_selected_name(menu),
			status = menu.status,
			blocked = menu_selected_blocked(menu),
		}
	}
	if .Rows in sections {
		state.rows = rows_state_build(hud, allocator)
	}
	if .Render_Digest in sections && render_digest != "" {
		state.render_digest = strings.clone(render_digest, allocator)
	}
	if sections == ALL_STATE_SECTIONS {
		state.digest = state_digest(state, allocator)
	}
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
