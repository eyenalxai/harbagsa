#+vet explicit-allocators
package renderer

import "src:ui"

Ui_Inspector :: struct {
	open:                  u32,
	has_selection:         u32,
	object_id:             u32,
	selection:             [^]u8,
	selection_len:         u32,
	body:                  u32,
	yaw_degrees:           f32,
	yaw_text:              [^]u8,
	yaw_text_len:          u32,
	placement_prefab:      [^]u8,
	placement_prefab_len:  u32,
	placement_height_text: [^]u8,
	placement_height_len:  u32,
	placement_yaw_text:    [^]u8,
	placement_yaw_len:     u32,
	placement_snap_text:   [^]u8,
	placement_snap_len:    u32,
	has_lamp:              u32,
	lamp_kind:             u32,
	lamp_color:            u32,
	lamp_intensity:        f32,
	lamp_range:            f32,
	lamp_intensity_text:   [^]u8,
	lamp_intensity_len:    u32,
	lamp_range_text:       [^]u8,
	lamp_range_len:        u32,
	lamp_colors:           [ui.INSPECTOR_LAMP_COLORS][4]f32,
	type_weight:           f32,
	type_weight_text:      [^]u8,
	type_weight_len:       u32,
	physics_debug:         u32,
}
