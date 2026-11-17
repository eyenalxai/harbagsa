#+vet explicit-allocators
package harness

import "core:mem"
import "core:strings"

import "src:game"
import "src:renderer"

Ui_Menu_State :: struct {
	open: bool   `json:"open"`,
	item: string `json:"item"`,
}

Ui_Palette_State :: struct {
	open:     bool `json:"open"`,
	selected: int  `json:"selected"`,
}

Ui_Inspector_State :: struct {
	open:          bool   `json:"open"`,
	selected_id:   u32    `json:"selected_id"`,
	section:       string `json:"section"`,
	scroll_offset: f32    `json:"scroll_offset"`,
	scroll_max:    f32    `json:"scroll_max"`,
}

Ui_Action_State :: struct {
	kind:   string `json:"kind"`,
	id:     u32    `json:"id"`,
	value:  i32    `json:"value"`,
	scalar: f32    `json:"scalar"`,
}

Ui_Viewport_State :: struct {
	width:  f32 `json:"width"`,
	height: f32 `json:"height"`,
}

Ui_Event_State :: struct {
	kind: string `json:"kind"`,
	key:  string `json:"key,omitempty"`,
	x:    f32    `json:"x"`,
	y:    f32    `json:"y"`,
	dx:   f32    `json:"dx,omitempty"`,
	dy:   f32    `json:"dy,omitempty"`,
	mods: u32    `json:"mods,omitempty"`,
}

Ui_State :: struct {
	surface:      string             `json:"surface"`,
	focus:        string             `json:"focus"`,
	hover:        string             `json:"hover"`,
	pressed:      string             `json:"pressed"`,
	pointer_free: bool               `json:"pointer_free"`,
	scale:        f32                `json:"scale"`,
	viewport:     Ui_Viewport_State  `json:"viewport"`,
	events:       []Ui_Event_State   `json:"events"`,
	actions:      []Ui_Action_State  `json:"actions"`,
	menu:         Ui_Menu_State      `json:"menu"`,
	palette:      Ui_Palette_State   `json:"palette"`,
	inspector:    Ui_Inspector_State `json:"inspector"`,
}

Ui_Observation :: struct {
	interaction:     renderer.Ui_Interaction,
	has_interaction: bool,
	actions:         []renderer.Ui_Action,
}

ui_action_kind_name :: proc(kind: u32) -> string {
	#partial switch renderer.UI_Action_Kind(kind) {
	case .Close_Menu:
		return "Close_Menu"
	case .Palette_Select:
		return "Palette_Select"
	case .Palette_Close:
		return "Palette_Close"
	case .Settings_Set:
		return "Settings_Set"
	case .Type_Weight_Set:
		return "Type_Weight_Set"
	case .Palette_Pick:
		return "Palette_Pick"
	case .Object_Set:
		return "Object_Set"
	case .Object_Duplicate:
		return "Object_Duplicate"
	case .Object_Delete:
		return "Object_Delete"
	case .Lamp_Set:
		return "Lamp_Set"
	case .Lamp_Kind:
		return "Lamp_Kind"
	case .Lamp_Color:
		return "Lamp_Color"
	case .Toggle_Inspector:
		return "Toggle_Inspector"
	case .Physics_Debug:
		return "Physics_Debug"
	}
	return "Unknown"
}

ui_action_kind_from_name :: proc(name: string) -> (kind: u32, ok: bool) {
	for value in renderer.UI_Action_Kind {
		if ui_action_kind_name(u32(value)) == name {
			return u32(value), true
		}
	}
	return 0, false
}

build_state_ui :: proc(state: ^State, ctx: ^State_Context) {
	focus := game.focus(ctx.debug, &ctx.hud.menu)
	view := game.editor_view(&ctx.debug.editor, ctx.sim, ctx.debug.active, ctx.debug.camera)
	selection, has_selection := view.selection.?
	inspector_open := focus.inspector_open
	selected_id: u32
	section := "placement"
	if has_selection {
		selected_id = u32(selection.id)
		section = selection.light.active ? "lamp" : "object"
	}
	state.ui = {
		surface      = ui_surface(focus.menu_open, inspector_open, view.palette.open),
		pointer_free = focus.pointer_free,
		menu = {open = focus.menu_open, item = game.menu_selected_name(&ctx.hud.menu)},
		palette = {open = view.palette.open, selected = int(view.palette.prefab)},
		inspector = {
			open = inspector_open,
			selected_id = selected_id,
			section = section,
		},
	}
	scale := ctx.renderer.ui_scale
	if scale > 0 {
		state.ui.scale = scale
		state.ui.viewport = {
			width  = f32(ctx.renderer.extent.width) / scale,
			height = f32(ctx.renderer.extent.height) / scale,
		}
	}
	if len(ctx.input.ui_events) > 0 {
		state.ui.events = make([]Ui_Event_State, len(ctx.input.ui_events), ctx.allocator)
		for event, index in ctx.input.ui_events {
			state.ui.events[index] = {
				kind = ui_event_kind_name(event.kind),
				key  = ui_event_key_name(event.key),
				x    = event.x,
				y    = event.y,
				dx   = event.dx,
				dy   = event.dy,
				mods = event.mods,
			}
		}
	}
	if ctx.ui.has_interaction {
		interaction := ctx.ui.interaction
		state.ui.focus = clone_interaction_key(interaction.focus[:], interaction.focus_len, ctx.allocator)
		state.ui.hover = clone_interaction_key(interaction.hover[:], interaction.hover_len, ctx.allocator)
		state.ui.pressed = clone_interaction_key(interaction.pressed[:], interaction.pressed_len, ctx.allocator)
		state.ui.inspector.scroll_offset = interaction.scroll_offset
		state.ui.inspector.scroll_max = interaction.scroll_max
	}
	if len(ctx.ui.actions) > 0 {
		state.ui.actions = make([]Ui_Action_State, len(ctx.ui.actions), ctx.allocator)
		for action, index in ctx.ui.actions {
			state.ui.actions[index] = {
				kind = ui_action_kind_name(action.kind),
				id = action.id,
				value = action.value,
				scalar = action.scalar,
			}
		}
	}
}

ui_state_destroy :: proc(state: ^Ui_State, allocator: mem.Allocator) {
	free_owned_string(&state.focus, allocator)
	free_owned_string(&state.hover, allocator)
	free_owned_string(&state.pressed, allocator)
	if state.actions != nil {
		delete(state.actions, allocator)
	}
	if state.events != nil {
		delete(state.events, allocator)
	}
	state^ = {}
}

@(private)
clone_interaction_key :: proc(bytes: []u8, length: u32, allocator: mem.Allocator) -> string {
	if length == 0 {
		return ""
	}
	count := min(int(length), len(bytes))
	return strings.clone(string(bytes[:count]), allocator)
}

@(private)
ui_surface :: proc(menu_open, inspector_open, palette_open: bool) -> string {
	if menu_open {
		return "settings"
	}
	if inspector_open {
		return "inspector"
	}
	if palette_open {
		return "palette"
	}
	return "hud"
}
@(private)
ui_event_kind_name :: proc(kind: u32) -> string {
	switch kind {
	case renderer.UI_EVENT_POINTER_MOVE:
		return "pointer_move"
	case renderer.UI_EVENT_POINTER_DOWN:
		return "pointer_down"
	case renderer.UI_EVENT_POINTER_UP:
		return "pointer_up"
	case renderer.UI_EVENT_POINTER_LEAVE:
		return "pointer_leave"
	case renderer.UI_EVENT_WHEEL:
		return "wheel"
	case renderer.UI_EVENT_KEY_DOWN:
		return "key_down"
	case renderer.UI_EVENT_KEY_UP:
		return "key_up"
	case renderer.UI_EVENT_KEY_REPEAT:
		return "key_repeat"
	case renderer.UI_EVENT_FOCUS:
		return "focus"
	}
	return "unknown"
}

@(private)
ui_event_key_name :: proc(key: i32) -> string {
	switch key {
	case renderer.UI_KEY_UP:
		return "Up"
	case renderer.UI_KEY_DOWN:
		return "Down"
	case renderer.UI_KEY_LEFT:
		return "Left"
	case renderer.UI_KEY_RIGHT:
		return "Right"
	case renderer.UI_KEY_ENTER:
		return "Enter"
	case renderer.UI_KEY_ESCAPE:
		return "Escape"
	case renderer.UI_KEY_TAB:
		return "Tab"
	case renderer.UI_KEY_SPACE:
		return "Space"
	}
	return ""
}
