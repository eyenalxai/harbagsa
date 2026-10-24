#+vet explicit-allocators
package harness

import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"

import b3 "libs:box3d"
import "src:digest"
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

Crate_State :: struct {
	position: Vec_State  `json:"position"`,
	rotation: Quat_State `json:"rotation"`,
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

Debug_State :: struct {
	active: bool `json:"active"`,
}

Sun_State :: struct {
	azimuth:          f32 `json:"azimuth"`,
	elevation:        f32 `json:"elevation"`,
	angular_diameter: f32 `json:"angular_diameter"`,
}

Menu_State :: struct {
	open:     bool   `json:"open"`,
	selected: int    `json:"selected"`,
	item:     string `json:"item"`,
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
	debug:              Renderer_Debug_State `json:"debug"`,
}

State :: struct {
	frame:         int            `json:"frame"`,
	player:        Player_State   `json:"player"`,
	crates:        []Crate_State  `json:"crates"`,
	settings:      Settings_State `json:"settings"`,
	debug:         Debug_State    `json:"debug"`,
	sun:           Sun_State      `json:"sun"`,
	menu:          Menu_State     `json:"menu"`,
	renderer:      Renderer_State `json:"renderer"`,
	render_digest: string         `json:"render_digest"`,
	digest:        string         `json:"digest"`,
}

state_build :: proc(
	sim: ^game.Simulation,
	frame: int,
	menu: ^game.Menu_State,
	debug: ^game.Debug_Mode,
	renderer_state: Renderer_State,
	render_digest: string,
	allocator: mem.Allocator,
) -> State {
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
		},
		sun = sun_state(debug),
		menu = {
			open = menu.open,
			selected = int(menu.selected),
			item = game.menu_selected_name(menu),
		},
		renderer = renderer_state,
		render_digest = render_digest == "" ? "" : strings.clone(render_digest, allocator),
	}
	crate_count := game.simulation_crate_count(sim)
	state.crates = make([]Crate_State, crate_count, allocator)
	for index in 0 ..< crate_count {
		box := game.simulation_crate_box(sim, index)
		state.crates[index] = {
			position = vec_state(box.center),
			rotation = Quat_State {
				x = box.rotation.x,
				y = box.rotation.y,
				z = box.rotation.z,
				w = box.rotation.w,
			},
		}
	}
	state.digest = state_digest(state, allocator)
	return state
}

state_destroy :: proc(state: ^State, allocator: mem.Allocator) {
	if state.crates != nil {
		delete(state.crates, allocator)
		state.crates = nil
	}
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
	digest.write_f32(&hash, state.settings.type_weight)
	digest.write_bool(&hash, state.menu.open)
	digest.write_i64(&hash, i64(state.menu.selected))
	digest.write_i64(&hash, i64(len(state.crates)))
	for crate in state.crates {
		digest.write_f32(&hash, crate.position.x)
		digest.write_f32(&hash, crate.position.y)
		digest.write_f32(&hash, crate.position.z)
		digest.write_f32(&hash, crate.rotation.x)
		digest.write_f32(&hash, crate.rotation.y)
		digest.write_f32(&hash, crate.rotation.z)
		digest.write_f32(&hash, crate.rotation.w)
	}
	return digest.hex(hash, allocator)
}

@(private)
vec_state :: proc(value: b3.Vec3) -> Vec_State {
	return {x = value.x, y = value.y, z = value.z}
}

@(private)
sun_state :: proc(debug: ^game.Debug_Mode) -> Sun_State {
	azimuth, elevation := game.debug_mode_sun_angles(debug)
	return {
		azimuth = math.to_degrees(azimuth),
		elevation = math.to_degrees(elevation),
		angular_diameter = math.to_degrees(debug.sun_angular_diameter),
	}
}
