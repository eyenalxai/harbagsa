#+vet explicit-allocators
package renderer

import "core:log"
import "core:mem"

import "src:platform"
import vk "vendor:vulkan"

Queue_Families :: struct {
	graphics: u32,
	present:  u32,
}

Swapchain_Support :: struct {
	capabilities: vk.SurfaceCapabilitiesKHR,
	formats:      []vk.SurfaceFormatKHR,
}

init_device :: proc(r: ^Renderer) -> Error {
	surface, surface_error := platform.create_vulkan_surface(r.window, r.instance)
	if surface_error != .None {
		return .Platform
	}
	r.surface = surface

	if err := select_physical_device(r); err != .None {
		return err
	}
	if err := create_logical_device(r); err != .None {
		return err
	}
	if status := create_swapchain(r); status != .Ok {
		return .Create_Swapchain
	}

	return .None
}

select_physical_device :: proc(r: ^Renderer) -> Error {
	count: u32
	if !check(vk.EnumeratePhysicalDevices(r.instance, &count, nil), "vkEnumeratePhysicalDevices") {
		return .No_Suitable_Device
	}
	if count == 0 {
		log.error("renderer: no Vulkan physical devices found; check the GPU driver and VK_ICD_FILENAMES")
		return .No_Suitable_Device
	}

	devices := make([]vk.PhysicalDevice, count, r.allocator)
	defer delete(devices, r.allocator)
	if !check(vk.EnumeratePhysicalDevices(r.instance, &count, raw_data(devices)), "vkEnumeratePhysicalDevices") {
		return .No_Suitable_Device
	}

	best_score := -1
	for device in devices {
		score, families, ok := score_physical_device(r, device)
		if !ok {
			continue
		}
		if score > best_score {
			best_score = score
			r.physical_device = device
			r.graphics_family = families.graphics
			r.present_family = families.present
		}
	}

	if r.physical_device == nil {
		log.error("renderer: no device supports graphics, present, swapchains, and dynamic rendering")
		return .No_Suitable_Device
	}
	vk.GetPhysicalDeviceMemoryProperties(r.physical_device, &r.memory_properties)
	return .None
}

score_physical_device :: proc(
	r: ^Renderer,
	device: vk.PhysicalDevice,
) -> (
	score: int,
	families: Queue_Families,
	ok: bool,
) {
	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(device, &props)
	name := name_from_bytes(props.deviceName[:])

	if props.apiVersion < vk.API_VERSION_1_3 {
		log.infof(
			"renderer: skipping %q: Vulkan %d.%d is older than 1.3",
			name,
			vk.API_VERSION_MAJOR(props.apiVersion),
			vk.API_VERSION_MINOR(props.apiVersion),
		)
		return
	}
	if !device_supports_extension(device, vk.KHR_SWAPCHAIN_EXTENSION_NAME, r.allocator) {
		log.infof("renderer: skipping %q: VK_KHR_swapchain is not supported", name)
		return
	}

	features13 := vk.PhysicalDeviceVulkan13Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
	}
	features2 := vk.PhysicalDeviceFeatures2 {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
		pNext = &features13,
	}
	vk.GetPhysicalDeviceFeatures2(device, &features2)
	if !features13.dynamicRendering {
		log.infof("renderer: skipping %q: dynamic rendering is not supported", name)
		return
	}

	queue_families, families_ok := find_queue_families(device, r.surface, r.allocator)
	if !families_ok {
		log.infof("renderer: skipping %q: no graphics and present queue pair", name)
		return
	}
	families = queue_families

	support, support_ok := query_swapchain_support(device, r.surface, r.allocator)
	if !support_ok {
		log.infof("renderer: skipping %q: swapchain is not supported", name)
		return
	}
	defer delete(support.formats, r.allocator)

	#partial switch props.deviceType {
	case .DISCRETE_GPU:
		score += 300_000
	case .INTEGRATED_GPU:
		score += 200_000
	case .VIRTUAL_GPU:
		score += 100_000
	case .CPU, .OTHER:
	}
	score += int(props.limits.maxImageDimension2D)

	log.infof("renderer: device %q scored %d", name, score)
	ok = true
	return
}

create_logical_device :: proc(r: ^Renderer) -> Error {
	queue_priorities := [1]f32{1.0}
	queue_infos: [2]vk.DeviceQueueCreateInfo
	queue_count: u32 = 1
	queue_infos[0] = vk.DeviceQueueCreateInfo{
		sType            = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = r.graphics_family,
		queueCount       = 1,
		pQueuePriorities = &queue_priorities[0],
	}
	if r.present_family != r.graphics_family {
		queue_infos[1] = vk.DeviceQueueCreateInfo{
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = r.present_family,
			queueCount       = 1,
			pQueuePriorities = &queue_priorities[0],
		}
		queue_count = 2
	}

	device_extensions := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}
	features13 := vk.PhysicalDeviceVulkan13Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		dynamicRendering = true,
	}
	create_info := vk.DeviceCreateInfo{
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = &features13,
		queueCreateInfoCount    = queue_count,
		pQueueCreateInfos       = &queue_infos[0],
		enabledExtensionCount   = u32(len(device_extensions)),
		ppEnabledExtensionNames = raw_data(device_extensions),
	}
	if !check(vk.CreateDevice(r.physical_device, &create_info, nil, &r.device), "vkCreateDevice") {
		return .Create_Device
	}
	vk.load_proc_addresses_device(r.device)
	vk.GetDeviceQueue(r.device, r.graphics_family, 0, &r.graphics_queue)
	vk.GetDeviceQueue(r.device, r.present_family, 0, &r.present_queue)

	return .None
}

find_queue_families :: proc(
	device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
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
	present_found := false
	for property, i in properties {
		if !graphics_found && .GRAPHICS in property.queueFlags {
			families.graphics = u32(i)
			graphics_found = true
		}
		supported: b32
		if vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), surface, &supported) == .SUCCESS && supported {
			if !present_found {
				families.present = u32(i)
				present_found = true
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

choose_swapchain_extent :: proc(capabilities: vk.SurfaceCapabilitiesKHR, window: ^platform.Window) -> vk.Extent2D {
	if capabilities.currentExtent.width != max(u32) {
		return capabilities.currentExtent
	}

	width, height := platform.pixel_size(window)
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
