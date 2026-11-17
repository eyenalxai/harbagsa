#+vet explicit-allocators
package harness

import "core:reflect"
import "core:strings"

import "src:game"
import "src:input"
import "src:platform"

// The harness speaks the platform enum names so a scenario can name any key,
// button, or modifier the engine knows without a second vocabulary.
key_name :: proc(key: platform.Key) -> string {
	name, _ := reflect.enum_name_from_value(key)
	return name
}

key_from_name :: proc(name: string) -> (platform.Key, bool) {
	for candidate in platform.Key {
		candidate_name, _ := reflect.enum_name_from_value(candidate)
		if strings.equal_fold(candidate_name, name) {
			return candidate, true
		}
	}
	return .None, false
}

modifier_name :: proc(modifier: platform.Modifier) -> string {
	name, _ := reflect.enum_name_from_value(modifier)
	return name
}

modifier_from_name :: proc(name: string) -> (platform.Modifier, bool) {
	for candidate in platform.Modifier {
		candidate_name, _ := reflect.enum_name_from_value(candidate)
		if strings.equal_fold(candidate_name, name) {
			return candidate, true
		}
	}
	return .Shift, false
}

gamepad_button_name :: proc(button: platform.Gamepad_Button) -> string {
	name, _ := reflect.enum_name_from_value(button)
	return name
}

gamepad_button_from_name :: proc(name: string) -> (platform.Gamepad_Button, bool) {
	for candidate in platform.Gamepad_Button {
		candidate_name, _ := reflect.enum_name_from_value(candidate)
		if strings.equal_fold(candidate_name, name) {
			return candidate, true
		}
	}
	return .South, false
}

input_kind_name :: proc(kind: platform.Input_Kind) -> string {
	#partial switch kind {
	case .Pointer_Move:
		return "pointer_move"
	case .Pointer_Down:
		return "pointer_down"
	case .Pointer_Up:
		return "pointer_up"
	case .Pointer_Leave:
		return "pointer_leave"
	case .Wheel:
		return "wheel"
	case .Key_Down:
		return "key_down"
	case .Key_Up:
		return "key_up"
	case .Key_Repeat:
		return "key_repeat"
	case .Focus_Gained:
		return "focus_gained"
	case .Focus_Lost:
		return "focus_lost"
	}
	return "unknown"
}

owner_name :: proc(owner: input.Owner) -> string {
	#partial switch owner {
	case .World:
		return "world"
	case .Menu:
		return "menu"
	case .Inspector:
		return "inspector"
	case .Palette:
		return "palette"
	case .Placement:
		return "placement"
	}
	return "unknown"
}

sink_name :: proc(sink: input.Sink) -> string {
	#partial switch sink {
	case .None:
		return "none"
	case .Game:
		return "game"
	case .UI:
		return "ui"
	}
	return "unknown"
}

// An action name is the union variant in snake_case, so a scenario asserts the
// intent the resolver produced without decoding a union.
edit_action_name :: proc(action: game.Edit_Action) -> string {
	switch value in action {
	case game.Palette_Open:
		return "palette_open"
	case game.Palette_Close:
		return "palette_close"
	case game.Palette_Select:
		return "palette_select"
	case game.Palette_Step:
		return "palette_step"
	case game.Palette_Flip_Body:
		return "palette_flip_body"
	case game.Palette_Pick:
		return "palette_pick"
	case game.Select_Object:
		return "select_object"
	case game.Move_Selected:
		return "move_selected"
	case game.Rotate_Selected:
		return "rotate_selected"
	case game.Turn:
		return "turn"
	case game.Set_Body:
		return "set_body"
	case game.Flip_Body:
		return "flip_body"
	case game.Delete_Selected:
		return "delete_selected"
	case game.Duplicate_Selected:
		return "duplicate_selected"
	case game.Undo:
		return "undo"
	case game.Redo:
		return "redo"
	case game.Inspector_Open:
		return "inspector_open"
	case game.Inspector_Close:
		return "inspector_close"
	case game.Inspector_Toggle:
		return "inspector_toggle"
	case game.Set_Selected_Yaw:
		return "set_selected_yaw"
	case game.Primary_Press:
		return "primary_press"
	case game.Primary_Release:
		return "primary_release"
	case game.Secondary_Press:
		return "secondary_press"
	case game.Drag_Move:
		return "drag_move"
	case game.Wheel:
		return "wheel"
	case game.Placement_Arm:
		return "placement_arm"
	case game.Placement_Cancel:
		return "placement_cancel"
	case game.Placement_Set_Height:
		return "placement_set_height"
	case game.Placement_Raise:
		return "placement_raise"
	case game.Placement_Set_Yaw:
		return "placement_set_yaw"
	case game.Placement_Turn:
		return "placement_turn"
	case game.Placement_Set_Snap:
		return "placement_set_snap"
	case game.Placement_Toggle_Snap:
		return "placement_toggle_snap"
	case game.Placement_Place:
		return "placement_place"
	case game.Place_Object:
		return "place_object"
	case game.Light_Adjust:
		return "light_adjust"
	case game.Light_Set_Color:
		return "light_set_color"
	case game.Light_Set_Intensity:
		return "light_set_intensity"
	case game.Light_Set_Range:
		return "light_set_range"
	case game.Light_Set_Kind:
		return "light_set_kind"
	case game.Light_Toggle_Kind:
		return "light_toggle_kind"
	case game.Cancel:
		return "cancel"
	}
	return "unknown"
}
