#+vet explicit-allocators
package renderer

import "base:runtime"
import "core:log"
import "core:mem"
import "core:strings"

import "src:platform"
import vk "vendor:vulkan"

// Validation layers are optional. Build with
//   odin build . -define:ENABLE_VALIDATION_LAYERS=true
// to turn them on when the layer is installed.
ENABLE_VALIDATION_LAYERS :: #config(ENABLE_VALIDATION_LAYERS, false)

MAX_FRAMES_IN_FLIGHT :: 2

VALIDATION_LAYER_NAME :: "VK_LAYER_KHRONOS_validation"

DEFAULT_CLEAR_COLOR :: [4]f32{0.10, 0.45, 0.75, 1.0}

COLOR_SUBRESOURCE :: vk.ImageSubresourceRange{
	aspectMask = {.COLOR},
	levelCount = 1,
	layerCount = 1,
}

Error :: enum {
	None,
	Vulkan_Loader,
	Vulkan_Version,
	Platform,
	Create_Instance,
	Create_Debug_Messenger,
	No_Suitable_Device,
	Create_Device,
	Create_Swapchain,
	Create_Frames,
	Create_Scene,
	Create_Pipeline,
}

// Frame_Status tells the main loop what to do with the frame it just started.
// Skipped means the swapchain moved out of date (or the window had no drawable
// area) and the frame must not be presented.
Frame_Status :: enum {
	Ok,
	Skipped,
	Fatal,
}

Frame :: struct {
	image_index:    u32,
	command_buffer: vk.CommandBuffer,
}

Queue_Families :: struct {
	graphics: u32,
	present:  u32,
}

Swapchain_Support :: struct {
	capabilities: vk.SurfaceCapabilitiesKHR,
	formats:      []vk.SurfaceFormatKHR,
}

Renderer :: struct {
	window:          ^platform.Window,
	allocator:       mem.Allocator,
	instance:        vk.Instance,
	debug_messenger: vk.DebugUtilsMessengerEXT,
	surface:         vk.SurfaceKHR,
	physical_device: vk.PhysicalDevice,
	memory_properties: vk.PhysicalDeviceMemoryProperties,
	device:          vk.Device,
	graphics_queue:  vk.Queue,
	present_queue:   vk.Queue,
	graphics_family: u32,
	present_family:  u32,

	swapchain:        vk.SwapchainKHR,
	swapchain_format: vk.Format,
	swapchain_extent: vk.Extent2D,
	swapchain_is_srgb: bool,
	swapchain_images: []vk.Image,
	swapchain_views:  []vk.ImageView,
	swapchain_dirty:  bool,

	command_pool:    vk.CommandPool,
	command_buffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	image_available: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	render_finished: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	in_flight:       [MAX_FRAMES_IN_FLIGHT]vk.Fence,
	frame_index:     int,
	clear_color:     [4]f32,

	scene: Scene,
}

// The validation callback runs outside the normal call stack, so it needs the
// logger context captured at init time.
g_context: runtime.Context

init :: proc(window: ^platform.Window, allocator: mem.Allocator) -> (r: Renderer, err: Error) {
	r.window = window
	r.allocator = allocator
	r.clear_color = DEFAULT_CLEAR_COLOR

	if err = init_instance(&r); err != .None {
		deinit(&r)
		return
	}
	if err = init_device(&r); err != .None {
		deinit(&r)
		return
	}
	if err = init_frames(&r); err != .None {
		deinit(&r)
		return
	}
	if err = init_scene(&r); err != .None {
		deinit(&r)
		return
	}

	return r, .None
}

deinit :: proc(r: ^Renderer) {
	if r.device != nil {
		_ = vk.DeviceWaitIdle(r.device)
	}

	destroy_scene(r)
	destroy_swapchain(r)

	if r.device != nil {
		for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
			if r.image_available[i] != 0 {
				vk.DestroySemaphore(r.device, r.image_available[i], nil)
				r.image_available[i] = 0
			}
			if r.render_finished[i] != 0 {
				vk.DestroySemaphore(r.device, r.render_finished[i], nil)
				r.render_finished[i] = 0
			}
			if r.in_flight[i] != 0 {
				vk.DestroyFence(r.device, r.in_flight[i], nil)
				r.in_flight[i] = 0
			}
		}
		if r.command_pool != 0 {
			vk.DestroyCommandPool(r.device, r.command_pool, nil)
			r.command_pool = 0
		}
		vk.DestroyDevice(r.device, nil)
		r.device = nil
	}

	if r.instance != nil {
		if r.debug_messenger != 0 {
			vk.DestroyDebugUtilsMessengerEXT(r.instance, r.debug_messenger, nil)
			r.debug_messenger = 0
		}
		if r.surface != 0 {
			platform.destroy_vulkan_surface(r.instance, r.surface)
			r.surface = 0
		}
		vk.DestroyInstance(r.instance, nil)
		r.instance = nil
	}
}

// notify_resize marks the swapchain for recreation on the next frame. The
// platform sends this on window resize and pixel-size changes, so the
// renderer does not compare the window size every frame.
notify_resize :: proc(r: ^Renderer) {
	r.swapchain_dirty = true
}

begin_frame :: proc(r: ^Renderer, camera: Camera, boxes: []Draw_Box) -> (frame: Frame, status: Frame_Status) {
	width, height := platform.pixel_size(r.window)
	if width == 0 || height == 0 {
		return {}, .Skipped
	}

	if r.swapchain_dirty {
		status = recreate_swapchain(r)
		if status != .Ok {
			return {}, status
		}
	}

	if !check(vk.WaitForFences(r.device, 1, &r.in_flight[r.frame_index], true, max(u64)), "vkWaitForFences") {
		return {}, .Fatal
	}

	image_index: u32
	acquire := vk.AcquireNextImageKHR(
		r.device,
		r.swapchain,
		max(u64),
		r.image_available[r.frame_index],
		0,
		&image_index,
	)
	#partial switch acquire {
	case .SUCCESS:
	case .SUBOPTIMAL_KHR:
		// The image is usable, but the swapchain should be rebuilt soon.
		r.swapchain_dirty = true
	case .ERROR_OUT_OF_DATE_KHR:
		r.swapchain_dirty = true
		return {}, .Skipped
	case:
		log.errorf("renderer: vkAcquireNextImageKHR failed: %v", acquire)
		return {}, .Fatal
	}

	if !check(vk.ResetFences(r.device, 1, &r.in_flight[r.frame_index]), "vkResetFences") {
		return {}, .Fatal
	}

	command_buffer := r.command_buffers[r.frame_index]
	if !check(vk.ResetCommandBuffer(command_buffer, {}), "vkResetCommandBuffer") {
		return {}, .Fatal
	}
	if !record_scene(r, command_buffer, image_index, camera, boxes) {
		return {}, .Fatal
	}

	return Frame{image_index = image_index, command_buffer = command_buffer}, .Ok
}

end_frame :: proc(r: ^Renderer, frame: Frame) -> Frame_Status {
	image_available := r.image_available[r.frame_index]
	render_finished := r.render_finished[r.frame_index]
	wait_stage := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
	command_buffer := frame.command_buffer
	image_index := frame.image_index

	submit := vk.SubmitInfo{
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &image_available,
		pWaitDstStageMask    = &wait_stage,
		commandBufferCount   = 1,
		pCommandBuffers      = &command_buffer,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &render_finished,
	}
	if !check(vk.QueueSubmit(r.graphics_queue, 1, &submit, r.in_flight[r.frame_index]), "vkQueueSubmit") {
		return .Fatal
	}

	present := vk.PresentInfoKHR{
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &render_finished,
		swapchainCount     = 1,
		pSwapchains        = &r.swapchain,
		pImageIndices      = &image_index,
	}
	present_result := vk.QueuePresentKHR(r.present_queue, &present)

	status: Frame_Status = .Ok
	#partial switch present_result {
	case .SUCCESS:
	case .SUBOPTIMAL_KHR:
		r.swapchain_dirty = true
	case .ERROR_OUT_OF_DATE_KHR:
		r.swapchain_dirty = true
		status = .Skipped
	case:
		log.errorf("renderer: vkQueuePresentKHR failed: %v", present_result)
		status = .Fatal
	}

	r.frame_index = (r.frame_index + 1) % MAX_FRAMES_IN_FLIGHT
	return status
}

init_instance :: proc(r: ^Renderer) -> Error {
	loader := platform.vulkan_loader_proc()
	if loader == nil {
		log.error("renderer: SDL did not provide vkGetInstanceProcAddr")
		return .Vulkan_Loader
	}
	vk.load_proc_addresses_global(loader)
	if vk.CreateInstance == nil || vk.EnumerateInstanceVersion == nil {
		log.error("renderer: Vulkan loader is missing required entry points")
		return .Vulkan_Loader
	}

	loader_version: u32
	if !check(vk.EnumerateInstanceVersion(&loader_version), "vkEnumerateInstanceVersion") {
		return .Vulkan_Version
	}
	if loader_version < vk.API_VERSION_1_3 {
		log.errorf(
			"renderer: Vulkan 1.3 is required, but the loader reports %d.%d",
			vk.API_VERSION_MAJOR(loader_version),
			vk.API_VERSION_MINOR(loader_version),
		)
		return .Vulkan_Version
	}

	extensions, platform_error := platform.vulkan_extensions()
	if platform_error != .None {
		return .Platform
	}

	instance_extensions := make([dynamic]cstring, 0, len(extensions) + 1, r.allocator)
	defer delete(instance_extensions)
	for extension in extensions {
		append(&instance_extensions, extension)
	}

	validation_enabled := false
	if ENABLE_VALIDATION_LAYERS {
		if validation_layer_available(r.allocator) && instance_extension_available(vk.EXT_DEBUG_UTILS_EXTENSION_NAME, r.allocator) {
			append(&instance_extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
			validation_enabled = true
			log.info("renderer: validation layers enabled")
		} else {
			log.warn("renderer: validation layers or VK_EXT_debug_utils are unavailable; continuing without validation")
		}
	}

	app_info := vk.ApplicationInfo{
		sType              = .APPLICATION_INFO,
		pApplicationName   = "harbagsa",
		applicationVersion = vk.MAKE_VERSION(0, 1, 0),
		pEngineName        = "harbagsa",
		engineVersion      = vk.MAKE_VERSION(0, 1, 0),
		apiVersion         = vk.API_VERSION_1_3,
	}
	create_info := vk.InstanceCreateInfo{
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = u32(len(instance_extensions)),
		ppEnabledExtensionNames = raw_data(instance_extensions),
	}
	if validation_enabled {
		validation_layers := []cstring{VALIDATION_LAYER_NAME}
		create_info.enabledLayerCount   = u32(len(validation_layers))
		create_info.ppEnabledLayerNames = raw_data(validation_layers)
	}

	if !check(vk.CreateInstance(&create_info, nil, &r.instance), "vkCreateInstance") {
		return .Create_Instance
	}
	vk.load_proc_addresses_instance(r.instance)

	if validation_enabled {
		g_context = context
		debug_info := vk.DebugUtilsMessengerCreateInfoEXT{
			sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = {.ERROR, .WARNING},
			messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE, .DEVICE_ADDRESS_BINDING},
			pfnUserCallback = debug_callback,
		}
		if !check(
			vk.CreateDebugUtilsMessengerEXT(r.instance, &debug_info, nil, &r.debug_messenger),
			"vkCreateDebugUtilsMessengerEXT",
		) {
			return .Create_Debug_Messenger
		}
	}

	return .None
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

init_frames :: proc(r: ^Renderer) -> Error {
	pool_info := vk.CommandPoolCreateInfo{
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = r.graphics_family,
	}
	if !check(vk.CreateCommandPool(r.device, &pool_info, nil, &r.command_pool), "vkCreateCommandPool") {
		return .Create_Frames
	}

	alloc_info := vk.CommandBufferAllocateInfo{
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = r.command_pool,
		level              = .PRIMARY,
		commandBufferCount = MAX_FRAMES_IN_FLIGHT,
	}
	if !check(vk.AllocateCommandBuffers(r.device, &alloc_info, &r.command_buffers[0]), "vkAllocateCommandBuffers") {
		return .Create_Frames
	}

	semaphore_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if !check(
			vk.CreateSemaphore(r.device, &semaphore_info, nil, &r.image_available[i]),
			"vkCreateSemaphore",
		) {
			return .Create_Frames
		}
		if !check(
			vk.CreateSemaphore(r.device, &semaphore_info, nil, &r.render_finished[i]),
			"vkCreateSemaphore",
		) {
			return .Create_Frames
		}
		if !check(vk.CreateFence(r.device, &fence_info, nil, &r.in_flight[i]), "vkCreateFence") {
			return .Create_Frames
		}
	}

	return .None
}

select_physical_device :: proc(r: ^Renderer) -> Error {
	count: u32
	if !check(vk.EnumeratePhysicalDevices(r.instance, &count, nil), "vkEnumeratePhysicalDevices") {
		return .No_Suitable_Device
	}
	if count == 0 {
		log.error("renderer: no Vulkan physical devices found")
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

create_swapchain :: proc(r: ^Renderer) -> Frame_Status {
	support, support_ok := query_swapchain_support(r.physical_device, r.surface, r.allocator)
	if !support_ok {
		log.error("renderer: could not query swapchain support")
		return .Fatal
	}
	defer delete(support.formats, r.allocator)

	format := choose_surface_format(support.formats)
	extent := choose_swapchain_extent(support.capabilities, r.window)
	if extent.width == 0 || extent.height == 0 {
		log.warnf("renderer: swapchain extent is zero (%vx%v)", extent.width, extent.height)
		return .Skipped
	}

	r.swapchain_format = format.format
	r.swapchain_extent = extent
	r.swapchain_is_srgb = format.format == .B8G8R8A8_SRGB || format.format == .R8G8B8A8_SRGB

	image_count := support.capabilities.minImageCount + 1
	if support.capabilities.maxImageCount > 0 && image_count > support.capabilities.maxImageCount {
		image_count = support.capabilities.maxImageCount
	}

	create_info := vk.SwapchainCreateInfoKHR{
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = r.surface,
		minImageCount    = image_count,
		imageFormat      = format.format,
		imageColorSpace  = format.colorSpace,
		imageExtent      = extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT},
		preTransform     = support.capabilities.currentTransform,
		compositeAlpha   = choose_composite_alpha(support.capabilities.supportedCompositeAlpha),
		presentMode      = .FIFO,
		clipped          = true,
	}
	if r.graphics_family != r.present_family {
		create_info.imageSharingMode = .CONCURRENT
		create_info.queueFamilyIndexCount = 2
		create_info.pQueueFamilyIndices = raw_data([]u32{r.graphics_family, r.present_family})
	} else {
		create_info.imageSharingMode = .EXCLUSIVE
	}

	if !check(vk.CreateSwapchainKHR(r.device, &create_info, nil, &r.swapchain), "vkCreateSwapchainKHR") {
		return .Fatal
	}

	image_count_actual: u32
	if !check(
		vk.GetSwapchainImagesKHR(r.device, r.swapchain, &image_count_actual, nil),
		"vkGetSwapchainImagesKHR",
	) {
		return .Fatal
	}
	r.swapchain_images = make([]vk.Image, image_count_actual, r.allocator)
	if !check(
		vk.GetSwapchainImagesKHR(r.device, r.swapchain, &image_count_actual, raw_data(r.swapchain_images)),
		"vkGetSwapchainImagesKHR",
	) {
		return .Fatal
	}

	r.swapchain_views = make([]vk.ImageView, image_count_actual, r.allocator)
	for image, i in r.swapchain_images {
		view_info := vk.ImageViewCreateInfo{
			sType            = .IMAGE_VIEW_CREATE_INFO,
			image            = image,
			viewType         = .D2,
			format           = format.format,
			subresourceRange = COLOR_SUBRESOURCE,
		}
		if !check(vk.CreateImageView(r.device, &view_info, nil, &r.swapchain_views[i]), "vkCreateImageView") {
			return .Fatal
		}
	}

	if !create_depth_resources(r) {
		log.error("renderer: could not create depth resources")
		return .Fatal
	}

	log.infof(
		"renderer: swapchain %vx%v with %d images, format %v",
		extent.width,
		extent.height,
		image_count_actual,
		format.format,
	)
	return .Ok
}

destroy_swapchain :: proc(r: ^Renderer) {
	destroy_depth_resources(r)

	if r.device != nil {
		for view in r.swapchain_views {
			if view != 0 {
				vk.DestroyImageView(r.device, view, nil)
			}
		}
		if r.swapchain != 0 {
			vk.DestroySwapchainKHR(r.device, r.swapchain, nil)
			r.swapchain = 0
		}
	}

	if r.swapchain_views != nil {
		delete(r.swapchain_views, r.allocator)
		r.swapchain_views = nil
	}
	if r.swapchain_images != nil {
		delete(r.swapchain_images, r.allocator)
		r.swapchain_images = nil
	}
}

recreate_swapchain :: proc(r: ^Renderer) -> Frame_Status {
	width, height := platform.pixel_size(r.window)
	if width == 0 || height == 0 {
		r.swapchain_dirty = true
		return .Skipped
	}

	if !check(vk.DeviceWaitIdle(r.device), "vkDeviceWaitIdle") {
		return .Fatal
	}
	destroy_swapchain(r)
	if status := create_swapchain(r); status != .Ok {
		return status
	}
	if r.scene.pipeline != 0 && r.scene.pipeline_format != r.swapchain_format {
		destroy_pipeline(r)
		if !create_pipeline(r) {
			return .Fatal
		}
	}
	r.swapchain_dirty = false

	return .Ok
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

validation_layer_available :: proc(allocator: mem.Allocator) -> bool {
	count: u32
	if vk.EnumerateInstanceLayerProperties(&count, nil) != .SUCCESS || count == 0 {
		return false
	}
	properties := make([]vk.LayerProperties, count, allocator)
	defer delete(properties, allocator)
	if vk.EnumerateInstanceLayerProperties(&count, raw_data(properties)) != .SUCCESS {
		return false
	}
	for &property in properties {
		if name_from_bytes(property.layerName[:]) == VALIDATION_LAYER_NAME {
			return true
		}
	}
	return false
}

instance_extension_available :: proc(name: cstring, allocator: mem.Allocator) -> bool {
	count: u32
	if vk.EnumerateInstanceExtensionProperties(nil, &count, nil) != .SUCCESS || count == 0 {
		return false
	}
	properties := make([]vk.ExtensionProperties, count, allocator)
	defer delete(properties, allocator)
	if vk.EnumerateInstanceExtensionProperties(nil, &count, raw_data(properties)) != .SUCCESS {
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
	// Fall back to the first advertised format. The fragment stage will need
	// manual gamma when this is not an sRGB format.
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

debug_callback :: proc "system" (
	severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	_: vk.DebugUtilsMessageTypeFlagsEXT,
	data: ^vk.DebugUtilsMessengerCallbackDataEXT,
	_: rawptr,
) -> b32 {
	context = g_context

	level := log.Level.Debug
	if .ERROR in severity {
		level = .Error
	} else if .WARNING in severity {
		level = .Warning
	} else if .INFO in severity {
		level = .Info
	}
	log.logf(level, "vulkan: %s", data.pMessage)

	return false
}

name_from_bytes :: proc(bytes: []byte) -> string {
	return strings.truncate_to_byte(string(bytes), 0)
}

check :: proc(result: vk.Result, what: string, loc := #caller_location) -> bool {
	if result == .SUCCESS {
		return true
	}
	log.errorf("renderer: %s failed: %v", what, result, location = loc)
	return false
}
