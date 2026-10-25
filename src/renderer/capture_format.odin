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

Format_Info :: struct {
	name:        string,
	texel_bytes: int,
}

format_info :: proc(format: vk.Format) -> Format_Info {
	#partial switch format {
	case .R8G8B8A8_SRGB:
		return {"R8G8B8A8_SRGB", 4}
	case .B8G8R8A8_SRGB:
		return {"B8G8R8A8_SRGB", 4}
	case .R8G8B8A8_UNORM:
		return {"R8G8B8A8_UNORM", 4}
	case .B8G8R8A8_UNORM:
		return {"B8G8R8A8_UNORM", 4}
	case .R16G16B16A16_SFLOAT:
		return {"R16G16B16A16_SFLOAT", 8}
	case .R32G32B32A32_SFLOAT:
		return {"R32G32B32A32_SFLOAT", 16}
	case .D32_SFLOAT:
		return {"D32_SFLOAT", 4}
	}
	return {"unknown", 0}
}

format_name :: proc(format: vk.Format) -> string {
	return format_info(format).name
}

texel_bytes :: proc(format: vk.Format) -> int {
	return format_info(format).texel_bytes
}

