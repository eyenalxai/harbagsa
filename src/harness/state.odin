#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:strings"

import b3 "libs:box3d"
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
}

Menu_State :: struct {
	open:     bool   `json:"open"`,
	selected: int    `json:"selected"`,
	item:     string `json:"item"`,
}

State :: struct {
	frame:    int            `json:"frame"`,
	player:   Player_State   `json:"player"`,
	crates:   []Crate_State  `json:"crates"`,
	settings: Settings_State `json:"settings"`,
	menu:     Menu_State     `json:"menu"`,
	digest:   string         `json:"digest"`,
}

state_build :: proc(
	sim: ^game.Simulation,
	frame: int,
	menu: ^game.Menu_State,
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
		},
		menu = {
			open = menu.open,
			selected = int(menu.selected),
			item = game.menu_selected_name(menu),
		},
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
	hash: u64 = 0xcbf29ce484222325
	hash = digest_u64(hash, u64(state.frame))
	hash = digest_f32(hash, state.player.position.x)
	hash = digest_f32(hash, state.player.position.y)
	hash = digest_f32(hash, state.player.position.z)
	hash = digest_f32(hash, state.player.eye.x)
	hash = digest_f32(hash, state.player.eye.y)
	hash = digest_f32(hash, state.player.eye.z)
	hash = digest_f32(hash, state.player.velocity.x)
	hash = digest_f32(hash, state.player.velocity.y)
	hash = digest_f32(hash, state.player.velocity.z)
	hash = digest_f32(hash, state.player.yaw)
	hash = digest_f32(hash, state.player.pitch)
	hash = digest_u64(hash, state.player.grounded ? 1 : 0)
	hash = digest_string(hash, state.settings.window_mode)
	hash = digest_string(hash, state.settings.display)
	hash = digest_u64(hash, u64(state.settings.display_index))
	hash = digest_string(hash, state.settings.resolution)
	hash = digest_string(hash, state.settings.window_resolution)
	hash = digest_string(hash, state.settings.sprint_mode)
	hash = digest_string(hash, state.settings.crouch_mode)
	hash = digest_string(hash, state.settings.prone_mode)
	hash = digest_u64(hash, state.menu.open ? 1 : 0)
	hash = digest_u64(hash, u64(state.menu.selected))
	hash = digest_u64(hash, u64(len(state.crates)))
	for crate in state.crates {
		hash = digest_f32(hash, crate.position.x)
		hash = digest_f32(hash, crate.position.y)
		hash = digest_f32(hash, crate.position.z)
		hash = digest_f32(hash, crate.rotation.x)
		hash = digest_f32(hash, crate.rotation.y)
		hash = digest_f32(hash, crate.rotation.z)
		hash = digest_f32(hash, crate.rotation.w)
	}
	return fmt.aprintf("%016x", hash, allocator = allocator)
}

@(private)
digest_u64 :: proc(hash: u64, value: u64) -> u64 {
	result := hash
	shift: u64
	for shift < 8 {
		result = (result ~ (value >> (shift * 8))) * 0x100000001b3
		shift += 1
	}
	return result
}

@(private)
digest_string :: proc(hash: u64, text: string) -> u64 {
	result := hash
	for byte in text {
		result = (result ~ u64(byte)) * 0x100000001b3
	}
	return result
}

@(private)
digest_f32 :: proc(hash: u64, value: f32) -> u64 {
	return digest_u64(hash, u64(transmute(u32)value))
}

@(private)
vec_state :: proc(value: b3.Vec3) -> Vec_State {
	return {x = value.x, y = value.y, z = value.z}
}
