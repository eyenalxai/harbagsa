#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls this API; the game binary does not
package game

import b3 "libs:box3d"

MAX_EDIT_ACTIONS :: 32

// Every edit is one intent. The keyboard and the harness build this set, and
// `edit_apply` owns the rules so neither caller can drift from the other.
Edit_Action :: union #no_nil {
	Palette_Open,
	Palette_Close,
	Palette_Select,
	Palette_Step,
	Palette_Flip_Body,
	Palette_Pick,
	Select_Object,
	Move_Selected,
	Rotate_Selected,
	Turn,
	Set_Body,
	Flip_Body,
	Delete_Selected,
	Duplicate_Selected,
	Undo,
	Redo,
	Primary_Press,
	Primary_Release,
	Secondary_Press,
	Drag_Move,
	Wheel,
	Placement_Arm,
	Placement_Cancel,
	Placement_Set_Height,
	Placement_Raise,
	Placement_Set_Yaw,
	Placement_Turn,
	Placement_Set_Snap,
	Placement_Toggle_Snap,
	Placement_Place,
	Place_Object,
	Light_Adjust,
	Light_Set_Color,
	Light_Set_Intensity,
	Light_Set_Range,
	Light_Set_Kind,
	Light_Toggle_Kind,
	Cancel,
}

Palette_Open :: struct {}
Palette_Close :: struct {}
Palette_Select :: struct {
	index: int,
}
Palette_Step :: struct {
	delta: int,
}
Palette_Flip_Body :: struct {}
Palette_Pick :: struct {}
Select_Object :: struct {
	id: Object_Id,
}
Move_Selected :: struct {
	center: b3.Vec3,
}
Rotate_Selected :: struct {
	degrees: f32,
}
Turn :: struct {
	steps: int,
	large: bool,
}
Set_Body :: struct {
	mode: Body_Mode,
}
Flip_Body :: struct {}
Delete_Selected :: struct {}
Duplicate_Selected :: struct {}
Undo :: struct {}
Redo :: struct {}
Primary_Press :: struct {}
Primary_Release :: struct {}
Secondary_Press :: struct {}
Drag_Move :: struct {
	look_delta: [2]f32,
}
Wheel :: struct {
	steps: int,
	large: bool,
}
Placement_Arm :: struct {
	prefab: Prefab_Id,
}
Placement_Cancel :: struct {}
Placement_Set_Height :: struct {
	height: f32,
}
Placement_Raise :: struct {
	steps: int,
	large: bool,
}
Placement_Set_Yaw :: struct {
	yaw_deg: f32,
}
Placement_Turn :: struct {
	steps: int,
	large: bool,
}
Placement_Set_Snap :: struct {
	snap: bool,
}
Placement_Toggle_Snap :: struct {}
Placement_Place :: struct {}
Place_Object :: struct {
	prefab:    Prefab_Id,
	body_mode: Body_Mode,
	center:    b3.Vec3,
	yaw_rad:   f32,
}
Light_Adjust :: struct {
	change: Light_Change,
}
Light_Set_Color :: struct {
	color: Light_Color,
}
Light_Set_Intensity :: struct {
	intensity: f32,
}
Light_Set_Range :: struct {
	range: f32,
}
Light_Set_Kind :: struct {
	kind: Lamp_Kind,
}
Light_Toggle_Kind :: struct {}
Cancel :: struct {}

Edit_Context :: struct {
	menu_open: bool,
	captured:  bool,
}

Edit_Reason :: enum {
	None,
	Inactive,
	Menu_Open,
	Palette_Open,
	Placement_Armed,
	Unknown_Object,
	No_Selection,
	No_Lamp,
	Lamp_Body_Follows_Kind,
	Bad_Index,
	Not_Armed,
	Nothing_To_Undo,
	Nothing_To_Redo,
	No_Change,
	Failed,
}

Edit_Result :: struct {
	applied: bool,
	reason:  Edit_Reason,
}

edit_ok :: proc() -> Edit_Result {
	return {applied = true}
}

edit_no_change :: proc() -> Edit_Result {
	return {reason = .No_Change}
}

edit_fail :: proc(reason: Edit_Reason) -> Edit_Result {
	return {reason = reason}
}

// The open palette or the armed tool owns the next placement. Body and light
// edits use this one decision.
editor_uses_next_placement :: proc(dm: ^Debug_Mode) -> bool {
	return dm.palette.open || dm.placement.armed
}

edit_reason_message :: proc(reason: Edit_Reason) -> string {
	switch reason {
	case .None:
		return ""
	case .Inactive:
		return "editor needs debug mode"
	case .Menu_Open:
		return "the settings menu is open"
	case .Palette_Open:
		return "the object palette is open"
	case .Placement_Armed:
		return "the placement tool is armed"
	case .Unknown_Object:
		return "the object id does not exist"
	case .No_Selection:
		return "no object is selected"
	case .No_Lamp:
		return "the target is not a lamp"
	case .Lamp_Body_Follows_Kind:
		return "a lamp body follows its kind"
	case .Bad_Index:
		return "the palette index is out of range"
	case .Not_Armed:
		return "the placement tool is not armed"
	case .Nothing_To_Undo:
		return "nothing to undo"
	case .Nothing_To_Redo:
		return "nothing to redo"
	case .No_Change:
		return ""
	case .Failed:
		return "the edit failed"
	}
	return ""
}

