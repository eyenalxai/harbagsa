#+vet explicit-allocators
package renderer

import "core:log"
import "core:mem"
import "core:strings"

import "src:platform"
import vk "vendor:vulkan"

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

	if result := vk.CreateInstance(&create_info, nil, &r.instance); result != .SUCCESS {
		log.errorf("renderer: vkCreateInstance failed: %v", result)
		if result == .ERROR_INCOMPATIBLE_DRIVER {
			log.error("renderer: no Vulkan driver was found; check the installed ICD and VK_ICD_FILENAMES")
		}
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
