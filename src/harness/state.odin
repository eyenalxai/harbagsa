#+vet explicit-allocators
package harness

import "core:mem"

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

Color_State :: struct {
	r: f32 `json:"r"`,
	g: f32 `json:"g"`,
	b: f32 `json:"b"`,
	a: f32 `json:"a"`,
}

Player_State :: struct {
	position:  Vec_State `json:"position"`,
	eye:       Vec_State `json:"eye"`,
	velocity:  Vec_State `json:"velocity"`,
	yaw_deg:   f32       `json:"yaw_deg"`,
	pitch_deg: f32       `json:"pitch_deg"`,
	stance:    string    `json:"stance"`,
	grounded:  bool      `json:"grounded"`,
}

Camera_State :: struct {
	position:   Vec_State `json:"position"`,
	yaw_deg:    f32       `json:"yaw_deg"`,
	pitch_deg:  f32       `json:"pitch_deg"`,
	fov_deg:    f32       `json:"fov_deg"`,
	source:     string    `json:"source"`,
	overridden: bool      `json:"overridden"`,
}

Static_Box_State :: struct {
	center:       Vec_State  `json:"center"`,
	half_extents: Vec_State  `json:"half_extents"`,
	color:        Color_State `json:"color"`,
	rotation:     Quat_State `json:"rotation"`,
	emissive:     f32        `json:"emissive"`,
	visual_only:  bool       `json:"visual_only"`,
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

Notice_State :: struct {
	text: string `json:"text"`,
}

Settle_State :: struct {
	frames:    int  `json:"frames"`,
	converged: bool `json:"converged"`,
}

State :: struct {
	frame:         int            `json:"frame"`,
	player:        Player_State   `json:"player"`,
	static_boxes:  []Static_Box_State `json:"static_boxes" digest:"-"`,
	camera:        Camera_State   `json:"camera" digest:"-"`,
	objects:       []Object_State `json:"objects"`,
	settings:      Settings_State `json:"settings"`,
	debug:         Debug_State    `json:"debug" digest:"-"`,
	sun:           Sun_State      `json:"sun"`,
	menu:          Menu_State     `json:"menu"`,
	notice:        Notice_State   `json:"notice" digest:"-"`,
	rows:          Rows_State     `json:"rows" digest:"-"`,
	settle:        Settle_State   `json:"settle" digest:"-"`,
	renderer:      renderer.Renderer_Report `json:"renderer" digest:"-"`,
	render_digest: string         `json:"render_digest" digest:"-"`,
	digest:        string         `json:"digest" digest:"-"`,
}

State_Section :: enum {
	Player,
	Objects,
	Settings,
	Debug,
	Static_Boxes,
	Sun,
	Menu,
	Notice,
	Rows,
	Render_Digest,
}

State_Sections :: bit_set[State_Section]

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
		state_all_sections(),
		allocator,
	)
}

// A check names one namespace, so the build runs only that namespace's row.
// The base fields (frame, camera, settle, renderer) are always set. The digest
// is the one document that asks for every row.
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
	state := State {
		frame = frame,
		camera = camera,
		settle = settle,
		renderer = renderer_state,
	}
	ctx := State_Context {
		sim = sim,
		hud = hud,
		debug = debug,
		render_digest = render_digest,
		allocator = allocator,
	}
	for row in STATE_SECTION_ROWS {
		if row.section in sections {
			row.build(&state, &ctx)
		}
	}
	if sections == state_all_sections() {
		state.digest = state_digest(state, allocator)
	}
	return state
}

state_destroy :: proc(state: ^State, allocator: mem.Allocator) {
	if state.objects != nil {
		delete(state.objects, allocator)
		state.objects = nil
	}
	if state.static_boxes != nil {
		delete(state.static_boxes, allocator)
		state.static_boxes = nil
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
