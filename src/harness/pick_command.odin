#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:strings"

import "src:game"
import "src:renderer"

Pick_Object :: struct {
	kind:   string        `json:"kind"`,
	id:     Maybe(u32)    `json:"id,omitempty"`,
	name:   Maybe(string) `json:"name,omitempty"`,
	prefab: Maybe(string) `json:"prefab,omitempty"`,
	index:  Maybe(int)    `json:"index,omitempty"`,
}

Pick_Lightmap :: struct {
	rect:  [4]f32 `json:"rect"`,
	texel: [2]i32 `json:"texel"`,
}

Pick_Probe_Cell :: struct {
	base:    [3]i32 `json:"base"`,
	invalid: u32    `json:"invalid"`,
	inside:  bool   `json:"inside"`,
}

Pick_Terms :: struct {
	direct:   [3]f32 `json:"direct"`,
	shadow:   [3]f32 `json:"shadow"`,
	lightmap: [3]f32 `json:"lightmap"`,
	probe:    [3]f32 `json:"probe"`,
	emissive: [3]f32 `json:"emissive"`,
}

// The hit shape the session reply and `report.picks` share. A miss carries
// `hit: false` and no other key.
Pick_Result :: struct {
	hit:        bool                    `json:"hit"`,
	object:     Maybe(Pick_Object)      `json:"object,omitempty"`,
	prefab:     Maybe(string)           `json:"prefab,omitempty"`,
	distance:   Maybe(f32)              `json:"distance,omitempty"`,
	position:   Maybe([3]f32)           `json:"position,omitempty"`,
	normal:     Maybe([3]f32)           `json:"normal,omitempty"`,
	face:       Maybe(int)              `json:"face,omitempty"`,
	lightmap:   Maybe(Pick_Lightmap)    `json:"lightmap,omitempty"`,
	probe_cell: Maybe(Pick_Probe_Cell)  `json:"probe_cell,omitempty"`,
	terms:      Maybe(Pick_Terms)       `json:"terms,omitempty"`,
}

@(private)
parse_pick :: proc(object: json.Object, _allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "at"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	at, ok := vec2_int_field(object, "at")
	if !ok || at.x < 0 || at.y < 0 {
		return {}, format_error("%s", "'at' must be [x, y] pixels from the top left")
	}
	return {kind = .Pick, pick = {at = at}}, ""
}

session_pick :: proc(session: ^Session, command: Pick_Command) -> string {
	if !session.render.enabled {
		return format_error("%s", "pick requires a renderer; rendering is disabled")
	}
	if session.hud.menu.open {
		return format_error("%s", "menu is open; close the menu to pick")
	}
	if session.render.backend == nil || session.render.backend.pick == nil {
		return format_error("%s", "pick requires a renderer")
	}
	hit, failure, pick_error := session.render.backend.pick(
		session.render.backend.ctx,
		session,
		command.at,
	)
	if pick_error != "" {
		if failure == .Frame {
			session.render.failed = true
			session_failure(session, pick_error)
		}
		return pick_error
	}
	append(&session.picks, pick_result_build(&session.sim, hit, session.allocator))
	session_refresh_renderer(session)
	return ""
}

// The instance custom index is the box order `frame.build` produces: static
// arena boxes, then placed objects, then the spider.
@(private)
pick_result_build :: proc(
	sim: ^game.Simulation,
	hit: renderer.Pick_Hit,
	allocator: mem.Allocator,
) -> Pick_Result {
	if !hit.hit {
		return {hit = false}
	}
	result := Pick_Result{hit = true}
	arena_count := len(game.arena_static_boxes())
	objects := game.simulation_objects(sim)
	if hit.instance < u32(arena_count) {
		result.object = Pick_Object {
			kind  = "static_box",
			index = int(hit.instance),
		}
	} else if hit.instance < u32(arena_count + len(objects)) {
		object := objects[int(hit.instance) - arena_count]
		prefab := strings.clone(game.prefab_name(object.prefab), allocator)
		picked := Pick_Object {
			kind   = "object",
			id     = object.id,
			prefab = prefab,
		}
		if name := game.simulation_object_name(sim, object.id); name != "" {
			picked.name = strings.clone(name, allocator)
		}
		result.object = picked
		result.prefab = prefab
	} else {
		result.object = Pick_Object {
			kind  = "spider",
			index = int(hit.instance) - arena_count - len(objects),
		}
	}
	result.distance = hit.distance
	result.position = hit.position
	result.normal = hit.normal
	result.face = int(hit.face)
	result.lightmap = Pick_Lightmap {
		rect  = hit.lightmap_rect,
		texel = hit.lightmap_texel,
	}
	result.probe_cell = Pick_Probe_Cell {
		base    = hit.probe_base,
		invalid = hit.probe_invalid,
		inside  = hit.probe_inside,
	}
	result.terms = Pick_Terms {
		direct   = hit.direct,
		shadow   = hit.shadow,
		lightmap = hit.lightmap,
		probe    = hit.probe,
		emissive = hit.emissive,
	}
	return result
}

pick_result_destroy :: proc(result: ^Pick_Result, allocator: mem.Allocator) {
	object_prefab: rawptr
	if object, has_object := result.object.?; has_object {
		if name, has_name := object.name.?; has_name && name != "" {
			delete(name, allocator)
		}
		if prefab, has_prefab := object.prefab.?; has_prefab && prefab != "" {
			object_prefab = raw_data(prefab)
			delete(prefab, allocator)
		}
	}
	// The object and the top-level prefab share one allocation.
	if prefab, has_prefab := result.prefab.?;
	   has_prefab && prefab != "" && raw_data(prefab) != object_prefab {
		delete(prefab, allocator)
	}
	result^ = {}
}
