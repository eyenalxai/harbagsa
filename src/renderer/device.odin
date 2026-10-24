#+vet explicit-allocators
package renderer

import "core:log"

import vk "vendor:vulkan"

init_device :: proc(r: ^Renderer) -> Error {
	if err := select_physical_device(r); err != .None {
		return err
	}
	if err := create_logical_device(r); err != .None {
		return err
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
			r.timestamp_valid_bits = families.timestamp_valid_bits
		}
	}

	if r.physical_device == nil {
		log.error("renderer: no device supports the required Vulkan 1.3 features")
		return .No_Suitable_Device
	}
	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(r.physical_device, &props)
	r.timestamp_period = props.limits.timestampPeriod
	r.device_name = props.deviceName
	r.device_name_len = len(name_from_bytes(props.deviceName[:]))
	r.timing_available = r.timestamp_valid_bits > 0 && r.timestamp_period > 0
	if !r.timing_available {
		log.warn("renderer: the graphics queue cannot write timestamps; GPU timings are off")
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

	features_rq := vk.PhysicalDeviceRayQueryFeaturesKHR {
		sType = .PHYSICAL_DEVICE_RAY_QUERY_FEATURES_KHR,
	}
	features_as := vk.PhysicalDeviceAccelerationStructureFeaturesKHR {
		sType = .PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR,
		pNext = &features_rq,
	}
	features12 := vk.PhysicalDeviceVulkan12Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		pNext = &features_as,
	}
	features13 := vk.PhysicalDeviceVulkan13Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		pNext = &features12,
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
	if !features12.bufferDeviceAddress {
		log.infof("renderer: skipping %q: buffer device address is not supported", name)
		return
	}
	if !features_as.accelerationStructure {
		log.infof("renderer: skipping %q: acceleration structures are not supported", name)
		return
	}
	if !features_rq.rayQuery {
		log.infof("renderer: skipping %q: ray queries are not supported", name)
		return
	}

	if r.target.kind == .Swapchain {
		if !device_supports_extension(device, vk.KHR_SWAPCHAIN_EXTENSION_NAME, r.allocator) {
			log.infof("renderer: skipping %q: VK_KHR_swapchain is not supported", name)
			return
		}
	}
	if !device_supports_extension(device, vk.KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME, r.allocator) {
		log.infof("renderer: skipping %q: VK_KHR_acceleration_structure is not supported", name)
		return
	}
	if !device_supports_extension(device, vk.KHR_RAY_QUERY_EXTENSION_NAME, r.allocator) {
		log.infof("renderer: skipping %q: VK_KHR_ray_query is not supported", name)
		return
	}

	queue_families, families_ok := find_queue_families(
		device,
		r.target.surface,
		r.target.kind == .Swapchain,
		r.allocator,
	)
	if !families_ok {
		if r.target.kind == .Swapchain {
			log.infof("renderer: skipping %q: no graphics and present queue pair", name)
		} else {
			log.infof("renderer: skipping %q: no graphics queue", name)
		}
		return
	}
	families = queue_families

	if r.target.kind == .Swapchain {
		support, support_ok := query_swapchain_support(device, r.target.surface, r.allocator)
		if !support_ok {
			log.infof("renderer: skipping %q: swapchain is not supported", name)
			return
		}
		defer delete(support.formats, r.allocator)
	}

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

	device_extensions: [5]cstring
	device_extension_count: u32
	if r.target.kind == .Swapchain {
		device_extensions[device_extension_count] = vk.KHR_SWAPCHAIN_EXTENSION_NAME
		device_extension_count += 1
	}
	device_extensions[device_extension_count] = vk.KHR_BUFFER_DEVICE_ADDRESS_EXTENSION_NAME
	device_extension_count += 1
	device_extensions[device_extension_count] = vk.KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME
	device_extension_count += 1
	device_extensions[device_extension_count] = vk.KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME
	device_extension_count += 1
	device_extensions[device_extension_count] = vk.KHR_RAY_QUERY_EXTENSION_NAME
	device_extension_count += 1

	features_rq := vk.PhysicalDeviceRayQueryFeaturesKHR {
		sType = .PHYSICAL_DEVICE_RAY_QUERY_FEATURES_KHR,
		rayQuery = true,
	}
	features_as := vk.PhysicalDeviceAccelerationStructureFeaturesKHR {
		sType = .PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR,
		pNext = &features_rq,
		accelerationStructure = true,
	}
	features12 := vk.PhysicalDeviceVulkan12Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		pNext = &features_as,
		bufferDeviceAddress = true,
	}
	features13 := vk.PhysicalDeviceVulkan13Features {
		sType            = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		pNext            = &features12,
		dynamicRendering = true,
	}
	create_info := vk.DeviceCreateInfo{
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = &features13,
		queueCreateInfoCount    = queue_count,
		pQueueCreateInfos       = &queue_infos[0],
		enabledExtensionCount   = device_extension_count,
		ppEnabledExtensionNames = &device_extensions[0],
	}
	if !check(vk.CreateDevice(r.physical_device, &create_info, nil, &r.device), "vkCreateDevice") {
		return .Create_Device
	}
	vk.load_proc_addresses_device(r.device)
	vk.GetDeviceQueue(r.device, r.graphics_family, 0, &r.graphics_queue)
	if r.present_family != r.graphics_family {
		vk.GetDeviceQueue(r.device, r.present_family, 0, &r.present_queue)
	} else {
		r.present_queue = r.graphics_queue
	}

	return .None
}
