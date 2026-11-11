use std::ffi::{c_char, c_void};
use std::sync::OnceLock;

use ash::vk;
use ash::vk::Handle;

#[repr(C)]
pub struct UiVkConfig {
    pub instance: *mut c_void,
    pub physical_device: *mut c_void,
    pub graphics_family: u32,
    pub present_family: u32,
}

#[repr(C)]
pub struct UiVkDevice {
    pub device: *mut c_void,
    pub graphics_queue: *mut c_void,
    pub present_queue: *mut c_void,
}

struct Host {
    _instance: wgpu::Instance,
    _device: wgpu::Device,
    _queue: wgpu::Queue,
}

static HOST: OnceLock<usize> = OnceLock::new();
static EXTENSIONS: OnceLock<Vec<usize>> = OnceLock::new();

fn instance_extensions() -> Result<&'static Vec<usize>, String> {
    if let Some(list) = EXTENSIONS.get() {
        return Ok(list);
    }
    let entry = unsafe { ash::Entry::load() }.map_err(|e| format!("load Vulkan: {e}"))?;
    let extensions = wgpu::hal::vulkan::Instance::desired_extensions(
        &entry,
        vk::API_VERSION_1_3,
        wgpu::InstanceFlags::default(),
    )
    .map_err(|e| format!("wgpu instance extensions: {e}"))?;
    let list: Vec<usize> = extensions.iter().map(|e| e.as_ptr() as usize).collect();
    let _ = EXTENSIONS.set(list);
    Ok(EXTENSIONS.get().expect("extensions"))
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_vk_instance_extensions(count: *mut u32) -> *const *const c_char {
    let Ok(list) = instance_extensions() else {
        if !count.is_null() {
            unsafe { *count = 0 };
        }
        return std::ptr::null();
    };
    if !count.is_null() {
        unsafe { *count = list.len() as u32 };
    }
    list.as_ptr() as *const *const c_char
}

unsafe fn adopt(
    config: &UiVkConfig,
) -> Result<(UiVkDevice, Host), String> {
    let entry = ash::Entry::load().map_err(|e| format!("load Vulkan: {e}"))?;
    let instance_extensions = instance_extensions()?;
    let names: Vec<&std::ffi::CStr> = instance_extensions
        .iter()
        .map(|&p| unsafe { std::ffi::CStr::from_ptr(p as *const c_char) })
        .collect();

    let raw_instance = vk::Instance::from_raw(config.instance as u64);
    let ash_instance =
        ash::Instance::load(entry.static_fn(), raw_instance);
    let hal_instance = wgpu::hal::vulkan::Instance::from_raw(
        entry.clone(),
        ash_instance.clone(),
        vk::API_VERSION_1_3,
        0,
        None,
        names,
        wgpu::InstanceFlags::default(),
        wgpu::MemoryBudgetThresholds::default(),
        false,
        Some(Box::new(|| {})),
    )
    .map_err(|e| format!("adopt the instance: {e:?}"))?;
    let instance =
        wgpu::Instance::from_hal::<wgpu::hal::api::Vulkan>(hal_instance);

    let raw_physical = vk::PhysicalDevice::from_raw(config.physical_device as u64);
    let adapters = pollster::block_on(instance.enumerate_adapters(wgpu::Backends::VULKAN));
    let adapter = adapters
        .into_iter()
        .find(|a| unsafe { a.as_hal::<wgpu::hal::api::Vulkan>() }
            .is_some_and(|h| unsafe { h.raw_physical_device() } == raw_physical))
        .ok_or_else(|| "no wgpu adapter for the game physical device".to_string())?;
    let features = adapter.features();
    if !features.contains(wgpu::Features::EXPERIMENTAL_RAY_QUERY) {
        return Err("the adapter does not expose ray query to wgpu".into());
    }
    let features = wgpu::Features::EXPERIMENTAL_RAY_QUERY;
    let limits = adapter.limits();
    let hints = wgpu::MemoryHints::default();

    let hal_adapter = unsafe { adapter.as_hal::<wgpu::hal::api::Vulkan>() }
        .ok_or_else(|| "no Vulkan adapter".to_string())?;
    let mut extensions =
        unsafe { hal_adapter.required_device_extensions(features) };
    if config.present_family != u32::MAX
        && !extensions.contains(&ash::khr::swapchain::NAME)
    {
        extensions.push(ash::khr::swapchain::NAME);
    }
    let mut device_features =
        unsafe { hal_adapter.physical_device_features(&extensions, features) };

    let priority = [1.0f32];
    let mut queue_families = vec![config.graphics_family];
    if config.present_family != u32::MAX
        && config.present_family != config.graphics_family
    {
        queue_families.push(config.present_family);
    }
    let queues: Vec<vk::DeviceQueueCreateInfo> = queue_families
        .iter()
        .map(|family| {
            vk::DeviceQueueCreateInfo::default()
                .queue_family_index(*family)
                .queue_priorities(&priority)
        })
        .collect();
    let extension_ptrs: Vec<*const c_char> =
        extensions.iter().map(|e| e.as_ptr()).collect();
    let create_info = vk::DeviceCreateInfo::default()
        .queue_create_infos(&queues)
        .enabled_extension_names(&extension_ptrs);
    let create_info = device_features.add_to_device_create(create_info);

    let mut dynamic = vk::PhysicalDeviceDynamicRenderingFeatures::default()
        .dynamic_rendering(true);
    let mut demote =
        vk::PhysicalDeviceShaderDemoteToHelperInvocationFeatures::default()
            .shader_demote_to_helper_invocation(true);
    let create_info = create_info.push_next(&mut demote).push_next(&mut dynamic);

    let raw_device = ash_instance
        .create_device(raw_physical, &create_info, None)
        .map_err(|e| format!("vkCreateDevice: {e:?}"))?;
    let raw_device_handle = raw_device.handle();
    let graphics_queue = raw_device.get_device_queue(config.graphics_family, 0);
    let present_queue = if config.present_family == u32::MAX
        || config.present_family == config.graphics_family
    {
        graphics_queue
    } else {
        raw_device.get_device_queue(config.present_family, 0)
    };

    let open_device = unsafe {
        hal_adapter.device_from_raw(
            raw_device,
            Some(Box::new(|| {})),
            &extensions,
            features,
            &limits,
            &hints,
            config.graphics_family,
            0,
        )
    }
    .map_err(|e| format!("adopt the device: {e:?}"))?;
    let (device, queue) = unsafe {
        adapter.create_device_from_hal::<wgpu::hal::api::Vulkan>(
            open_device,
            &wgpu::DeviceDescriptor {
                label: Some("harbagsa-ui"),
                required_features: features,
                required_limits: limits,
                experimental_features: wgpu::ExperimentalFeatures::disabled(),
                memory_hints: hints,
                trace: wgpu::Trace::Off,
            },
        )
    }
    .map_err(|e| format!("create the wgpu device: {e}"))?;

    Ok((
        UiVkDevice {
            device: raw_device_handle.as_raw() as *mut c_void,
            graphics_queue: graphics_queue.as_raw() as *mut c_void,
            present_queue: present_queue.as_raw() as *mut c_void,
        },
        Host {
            _instance: instance,
            _device: device,
            _queue: queue,
        },
    ))
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_vk_init(
    config: *const UiVkConfig,
    out: *mut UiVkDevice,
) -> i32 {
    if config.is_null() || out.is_null() {
        return 1;
    }
    let config = unsafe { &*config };
    match unsafe { adopt(config) } {
        Ok((device, host)) => {
            let host = Box::leak(Box::new(host));
            let _ = HOST.set(host as *mut Host as usize);
            unsafe { *out = device };
            0
        }
        Err(error) => {
            eprintln!("harbagsa-ui: {error}");
            1
        }
    }
}
