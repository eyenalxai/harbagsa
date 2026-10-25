#+vet explicit-allocators
package harness

import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"

import "src:display"
import "src:game"

// The one list of conditional state sections. The build, the check resolver,
// and the all-sections set read it.
State_Section_Row :: struct {
	section: State_Section,
	field:   string,
	build:   proc(state: ^State, ctx: ^State_Context),
}

State_Context :: struct {
	sim:           ^game.Simulation,
	hud:           ^game.HUD_State,
	debug:         ^game.Debug_Mode,
	render_digest: string,
	allocator:     mem.Allocator,
}

STATE_SECTION_ROWS := [?]State_Section_Row {
	{.Player, "player", build_state_player},
	{.Static_Boxes, "static_boxes", build_state_static_boxes},
	{.Objects, "objects", build_state_objects},
	{.Settings, "settings", build_state_settings},
	{.Debug, "debug", build_state_debug},
	{.Sun, "sun", build_state_sun},
	{.Menu, "menu", build_state_menu},
	{.Notice, "notice", build_state_notice},
	{.Rows, "rows", build_state_rows},
	{.Render_Digest, "render_digest", build_state_render_digest},
}

state_all_sections :: proc() -> State_Sections {
	sections: State_Sections
	for row in STATE_SECTION_ROWS {
		sections |= {row.section}
	}
	return sections
}

// A check names one namespace. The table is the same list the build reads, so
// a check cannot ask for a document it will not address. The base fields
// (frame, camera, settle, renderer) need no section.
state_section_for_field :: proc(field: string) -> State_Sections {
	head, _, _ := split_field(field)
	if head == "digest" {
		return state_all_sections()
	}
	for row in STATE_SECTION_ROWS {
		if row.field == head {
			return {row.section}
		}
	}
	return {}
}

@(private)
build_state_player :: proc(state: ^State, ctx: ^State_Context) {
	snapshot := game.simulation_snapshot(ctx.sim)
	state.player = {
		position = vec_state(snapshot.position),
		eye = vec_state(snapshot.eye_position),
		velocity = vec_state(snapshot.velocity),
		yaw_deg = f32(math.to_degrees(snapshot.yaw)),
		pitch_deg = f32(math.to_degrees(snapshot.pitch)),
		stance = game.stance_name(snapshot.stance),
		grounded = snapshot.grounded,
	}
}

@(private)
build_state_static_boxes :: proc(state: ^State, ctx: ^State_Context) {
	boxes := game.arena_static_boxes()
	state.static_boxes = make([]Static_Box_State, len(boxes), ctx.allocator)
	for box, index in boxes {
		state.static_boxes[index] = {
			center = vec_state(box.center),
			half_extents = vec_state(box.half_extents),
			color = color_state(box.color),
			rotation = quat_state(box.rotation),
			emissive = box.emissive,
			visual_only = box.visual_only,
		}
	}
}

@(private)
build_state_objects :: proc(state: ^State, ctx: ^State_Context) {
	objects := game.simulation_objects(ctx.sim)
	state.objects = make([]Object_State, len(objects), ctx.allocator)
	for object, index in objects {
		box := game.simulation_object_box(ctx.sim, object.id)
		state.objects[index] = {
			id        = u32(object.id),
			prefab    = game.prefab_name(object.prefab),
			body      = game.body_mode_name(object.body_mode),
			position  = vec_state(box.center),
			rotation  = quat_state(box.rotation),
			scale     = game.simulation_object_scale(ctx.sim, object.id),
			spawn_age = game.simulation_object_spawn_age(ctx.sim, object.id),
			light     = light_state(object.light),
		}
	}
}

@(private)
build_state_settings :: proc(state: ^State, ctx: ^State_Context) {
	settings := &ctx.sim.settings
	resolution := game.settings_effective_resolution(settings)
	window_resolution := settings.window.resolution
	state.settings = {
		window_mode = game.window_mode_name(settings.window.mode),
		display = strings.clone(game.settings_display_name(settings), ctx.allocator),
		display_index = display.clamp_index(&settings.display, settings.window.display),
		resolution = fmt.aprintf(
			"%dx%d",
			resolution.width,
			resolution.height,
			allocator = ctx.allocator,
		),
		window_resolution = fmt.aprintf(
			"%dx%d",
			window_resolution.width,
			window_resolution.height,
			allocator = ctx.allocator,
		),
		sprint_mode = game.input_mode_name(settings.sprint_mode),
		crouch_mode = game.input_mode_name(settings.crouch_mode),
		prone_mode = game.input_mode_name(settings.prone_mode),
		type_weight = settings.type_weight,
	}
}

@(private)
build_state_debug :: proc(state: ^State, ctx: ^State_Context) {
	sun := sun_state(ctx.debug)
	state.debug = debug_state_build(ctx.debug, ctx.sim, sun)
}

@(private)
build_state_sun :: proc(state: ^State, ctx: ^State_Context) {
	state.sun = sun_state(ctx.debug)
}

@(private)
build_state_menu :: proc(state: ^State, ctx: ^State_Context) {
	menu := &ctx.hud.menu
	state.menu = {
		open = menu.open,
		selected = int(menu.selected),
		item = game.menu_selected_name(menu),
		status = menu.status,
		blocked = menu_selected_blocked(menu),
	}
}

@(private)
build_state_notice :: proc(state: ^State, ctx: ^State_Context) {
	state.notice = {text = game.hud_notice_text(ctx.hud)}
}

@(private)
build_state_rows :: proc(state: ^State, ctx: ^State_Context) {
	state.rows = rows_state_build(ctx.hud, ctx.allocator)
}

@(private)
build_state_render_digest :: proc(state: ^State, ctx: ^State_Context) {
	if ctx.render_digest != "" {
		state.render_digest = strings.clone(ctx.render_digest, ctx.allocator)
	}
}
