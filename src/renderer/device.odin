#+vet explicit-allocators
package renderer

import "core:log"

import "src:platform"
import vk "vendor:vulkan"

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
