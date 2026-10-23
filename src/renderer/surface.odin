#+vet explicit-allocators
package renderer

import "core:log"
import "core:mem"

import vk "vendor:vulkan"

Queue_Families :: struct {
	graphics: u32,
	present:  u32,
}

Swapchain_Support :: struct {
	capabilities: vk.SurfaceCapabilitiesKHR,
	formats:      []vk.SurfaceFormatKHR,
}

find_queue_families :: proc(
	device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
	require_present: bool,
	allocator: mem.Allocator,
) -> (
	families: Queue_Families,
	ok: bool,
) {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, nil)
	if count == 0 {
		return {}, false
	}

	properties := make([]vk.QueueFamilyProperties, count, allocator)
	defer delete(properties, allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, raw_data(properties))

	graphics_found := false
	present_found := !require_present
	for property, i in properties {
		if !graphics_found && .GRAPHICS in property.queueFlags {
			families.graphics = u32(i)
			graphics_found = true
			if !require_present {
				families.present = u32(i)
			}
		}
		if require_present {
			supported: b32
			if vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), surface, &supported) == .SUCCESS && supported {
				if !present_found {
					families.present = u32(i)
					present_found = true
				}
			}
		}
		if graphics_found && present_found {
			break
		}
	}

	return families, graphics_found && present_found
}

query_swapchain_support :: proc(
	device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
	allocator: mem.Allocator,
) -> (
	support: Swapchain_Support,
	ok: bool,
) {
	if vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &support.capabilities) != .SUCCESS {
		return {}, false
	}

	count: u32
	if vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &count, nil) != .SUCCESS || count == 0 {
		return {}, false
	}
	support.formats = make([]vk.SurfaceFormatKHR, count, allocator)
	if vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &count, raw_data(support.formats)) != .SUCCESS {
		delete(support.formats, allocator)
		return {}, false
	}

	return support, true
}

device_supports_extension :: proc(device: vk.PhysicalDevice, name: cstring, allocator: mem.Allocator) -> bool {
	count: u32
	if vk.EnumerateDeviceExtensionProperties(device, nil, &count, nil) != .SUCCESS || count == 0 {
		return false
	}
	properties := make([]vk.ExtensionProperties, count, allocator)
	defer delete(properties, allocator)
	if vk.EnumerateDeviceExtensionProperties(device, nil, &count, raw_data(properties)) != .SUCCESS {
		return false
	}
	for &property in properties {
		if name_from_bytes(property.extensionName[:]) == string(name) {
			return true
		}
	}
	return false
}

choose_surface_format :: proc(formats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
	for format in formats {
		if format.colorSpace != .SRGB_NONLINEAR {
			continue
		}
		#partial switch format.format {
		case .B8G8R8A8_SRGB, .R8G8B8A8_SRGB:
			return format
		}
	}
	// The fragment stage needs manual gamma when this is not sRGB.
	log.warnf("renderer: no sRGB swapchain format; falling back to %v", formats[0].format)
	return formats[0]
}

choose_swapchain_extent :: proc(
	capabilities: vk.SurfaceCapabilitiesKHR,
	width, height: u32,
) -> vk.Extent2D {
	if capabilities.currentExtent.width != max(u32) {
		return capabilities.currentExtent
	}

	return vk.Extent2D {
		width = clamp(width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
		height = clamp(height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
	}
}

choose_composite_alpha :: proc(supported: vk.CompositeAlphaFlagsKHR) -> vk.CompositeAlphaFlagsKHR {
	if .OPAQUE in supported {
		return {.OPAQUE}
	}
	if .PRE_MULTIPLIED in supported {
		return {.PRE_MULTIPLIED}
	}
	if .POST_MULTIPLIED in supported {
		return {.POST_MULTIPLIED}
	}
	return {.INHERIT}
}
