#+vet explicit-allocators
#+vet !unused-procedures // the harness and the renderer read these names
package renderer

import vk "vendor:vulkan"

capture_target_name :: proc(target: Capture_Target) -> string {
	switch target {
	case .Color:
		return "color"
	case .Velocity:
		return "velocity"
	case .History:
		return "history"
	case .Depth:
		return "depth"
	case .Scene_Color:
		return "scene_color"
	}
	return "color"
}

capture_target_parse :: proc(name: string) -> (target: Capture_Target, ok: bool) {
	switch name {
	case "color":
		return .Color, true
	case "velocity":
		return .Velocity, true
	case "history":
		return .History, true
	case "depth":
		return .Depth, true
	case "scene_color":
		return .Scene_Color, true
	}
	return .Color, false
}

// How `capture_values` turns the texel bytes into four floats.
Capture_Decode :: enum {
	Unknown,
	Rgba8,
	Rgba16f,
	Rgba32f,
	Depth32f,
}

Format_Info :: struct {
	name:        string,
	texel_bytes: int,
	decode:      Capture_Decode,
}

Capture_Format_Entry :: struct {
	format: vk.Format,
	info:   Format_Info,
}

// One row per readable capture format. A new format changes this table and the
// decoder, not a second format switch.
CAPTURE_FORMATS := [?]Capture_Format_Entry {
	{.R8G8B8A8_SRGB, {"R8G8B8A8_SRGB", 4, .Rgba8}},
	{.B8G8R8A8_SRGB, {"B8G8R8A8_SRGB", 4, .Rgba8}},
	{.R8G8B8A8_UNORM, {"R8G8B8A8_UNORM", 4, .Rgba8}},
	{.B8G8R8A8_UNORM, {"B8G8R8A8_UNORM", 4, .Rgba8}},
	{.R16G16B16A16_SFLOAT, {"R16G16B16A16_SFLOAT", 8, .Rgba16f}},
	{.R32G32B32A32_SFLOAT, {"R32G32B32A32_SFLOAT", 16, .Rgba32f}},
	{.D32_SFLOAT, {"D32_SFLOAT", 4, .Depth32f}},
}

format_info :: proc(format: vk.Format) -> Format_Info {
	for entry in CAPTURE_FORMATS {
		if entry.format == format {
			return entry.info
		}
	}
	return {"unknown", 0, .Unknown}
}

format_name :: proc(format: vk.Format) -> string {
	return format_info(format).name
}

texel_bytes :: proc(format: vk.Format) -> int {
	return format_info(format).texel_bytes
}
