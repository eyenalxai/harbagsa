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

Ui_State :: struct {
	surface:      string             `json:"surface"`,
	focus:        string             `json:"focus"`,
	hover:        string             `json:"hover"`,
	pressed:      string             `json:"pressed"`,
	pointer_free: bool               `json:"pointer_free"`,
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
	case .Debug_Inspector:
		return "Debug_Inspector"
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