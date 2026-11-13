use std::ffi::{c_char, c_void};
use std::sync::OnceLock;

use ash::vk;
use ash::vk::Handle;
use rune::render::Renderer;
use rune::text::TextSystem;
use rune::{Env, Runtime};
use rune_fx::{FxOptions, FxRenderer};

use crate::abi::{UiTarget, UiVkConfig, UiVkDevice};
use crate::state::UiState;
use crate::views;

const GEIST: &[u8] = include_bytes!("../assets/Geist-Variable.ttf");
const GEIST_MONO: &[u8] = include_bytes!("../assets/GeistMono-Variable.ttf");

pub struct Host {
    _instance: wgpu::Instance,
    pub(crate) device: wgpu::Device,
    pub(crate) queue: wgpu::Queue,
    pub(crate) format: Option<wgpu::TextureFormat>,
    pub(crate) runtime: Option<Runtime<UiState>>,
    pub(crate) renderer: Option<Renderer>,
    pub(crate) fx: Option<FxRenderer>,
    textures: Vec<wgpu::Texture>,
    pub(crate) views: Vec<wgpu::TextureView>,
    pub(crate) width: u32,
    pub(crate) height: u32,
    pub(crate) scale: f32,
}

static HOST: OnceLock<usize> = OnceLock::new();
static EXTENSIONS: OnceLock<Vec<usize>> = OnceLock::new();

pub fn instance_extensions() -> Result<&'static Vec<usize>, String> {
    if let Some(list) = EXTENSIONS.get() {
        return Ok(list);
    }
    // SAFETY: The Vulkan loader is process-global and loaded by the game.
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

pub fn init_vk(config: *const UiVkConfig, out: *mut UiVkDevice) -> i32 {
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

/// Adopt the game's Vulkan instance and physical device.
///
/// # Safety
///
/// `config` must point at a live Vulkan instance and physical device created by
/// the game. The queue families must be valid for that physical device, and the
/// game must not destroy the instance or device while the returned `Host` lives.
unsafe fn adopt(config: &UiVkConfig) -> Result<(UiVkDevice, Host), String> {
    // SAFETY: The game has already initialized Vulkan, so the loader is loaded
    // in this process; `Entry::load` only resolves its entry points.
    let entry = unsafe { ash::Entry::load() }.map_err(|e| format!("load Vulkan: {e}"))?;
    let instance_extensions = instance_extensions()?;
    // SAFETY: The extension names are static NUL-terminated strings owned by
    // the Vulkan loader.
    let names: Vec<&std::ffi::CStr> = instance_extensions
        .iter()
        .map(|&p| unsafe { std::ffi::CStr::from_ptr(p as *const c_char) })
        .collect();

    let raw_instance = vk::Instance::from_raw(config.instance as u64);
    // SAFETY: `raw_instance` is the game's live instance and `entry` was loaded
    // from the same loader.
    let ash_instance = unsafe { ash::Instance::load(entry.static_fn(), raw_instance) };
    // SAFETY: The entry, instance, and extension names are live; wgpu takes
    // ownership of the HAL instance.
    let hal_instance = unsafe {
        wgpu::hal::vulkan::Instance::from_raw(
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
    }
    .map_err(|e| format!("adopt the instance: {e:?}"))?;
    // SAFETY: `hal_instance` is a valid HAL instance that wgpu now owns.
    let instance = unsafe { wgpu::Instance::from_hal::<wgpu::hal::api::Vulkan>(hal_instance) };

    let raw_physical = vk::PhysicalDevice::from_raw(config.physical_device as u64);
    let adapters = pollster::block_on(instance.enumerate_adapters(wgpu::Backends::VULKAN));
    let adapter = adapters
        .into_iter()
        .find(|a| {
            unsafe { a.as_hal::<wgpu::hal::api::Vulkan>() }
                .is_some_and(|h| h.raw_physical_device() == raw_physical)
        })
        .ok_or_else(|| "no wgpu adapter for the game physical device".to_string())?;
    let features = adapter.features();
    if !features.contains(wgpu::Features::EXPERIMENTAL_RAY_QUERY) {
        return Err("the adapter does not expose ray query to wgpu".into());
    }
    let features = wgpu::Features::EXPERIMENTAL_RAY_QUERY;
    let limits = adapter.limits();
    let hints = wgpu::MemoryHints::default();

    // SAFETY: The adapter is a live Vulkan adapter; the HAL handle is valid
    // while `adapter` lives.
    let hal_adapter = unsafe { adapter.as_hal::<wgpu::hal::api::Vulkan>() }
        .ok_or_else(|| "no Vulkan adapter".to_string())?;
    let mut extensions = hal_adapter.required_device_extensions(features);
    if config.present_family != u32::MAX && !extensions.contains(&ash::khr::swapchain::NAME) {
        extensions.push(ash::khr::swapchain::NAME);
    }
    let mut device_features = hal_adapter.physical_device_features(&extensions, features);

    let priority = [1.0f32];
    let mut queue_families = vec![config.graphics_family];
    if config.present_family != u32::MAX && config.present_family != config.graphics_family {
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
    let extension_ptrs: Vec<*const c_char> = extensions.iter().map(|e| e.as_ptr()).collect();
    let create_info = vk::DeviceCreateInfo::default()
        .queue_create_infos(&queues)
        .enabled_extension_names(&extension_ptrs);
    let create_info = device_features.add_to_device_create(create_info);

    let mut dynamic = vk::PhysicalDeviceDynamicRenderingFeatures::default().dynamic_rendering(true);
    let mut demote = vk::PhysicalDeviceShaderDemoteToHelperInvocationFeatures::default()
        .shader_demote_to_helper_invocation(true);
    let create_info = create_info.push_next(&mut demote).push_next(&mut dynamic);

    // SAFETY: The caller guarantees the physical device and queue families; the
    // extensions and features came from this adapter; the HAL device owns the
    // returned raw device.
    let raw_device =
        unsafe { ash_instance.create_device(raw_physical, &create_info, None) }
            .map_err(|e| format!("vkCreateDevice: {e:?}"))?;
    let raw_device_handle = raw_device.handle();
    // SAFETY: The device was created with this queue family; index 0 is valid.
    let graphics_queue = unsafe { raw_device.get_device_queue(config.graphics_family, 0) };
    let present_queue = if config.present_family == u32::MAX
        || config.present_family == config.graphics_family
    {
        graphics_queue
    } else {
        // SAFETY: The present family was included in the queue create infos
        // above; index 0 is valid.
        unsafe { raw_device.get_device_queue(config.present_family, 0) }
    };

    // SAFETY: The raw device was created from this adapter with the requested
    // extensions and features; wgpu takes ownership of it.
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
    // SAFETY: The HAL device came from this adapter and is not used elsewhere;
    // wgpu takes ownership of it.
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
            device,
            queue,
            format: None,
            runtime: None,
            renderer: None,
            fx: None,
            textures: Vec::new(),
            views: Vec::new(),
            width: 0,
            height: 0,
            scale: 1.0,
        },
    ))
}

pub fn attach(target: *const UiTarget) -> i32 {
    if target.is_null() {
        return 1;
    }
    let target = unsafe { &*target };
    let Some(host) = host() else { return 2 };
    let Some(format) = texture_format(target.format) else {
        eprintln!("harbagsa-ui: unsupported target format {}", target.format);
        return 3;
    };
    if target.images.is_null() || target.image_count == 0 {
        return 4;
    }

    let mut textures = Vec::new();
    let mut views = Vec::new();
    {
        let Some(hal) = (unsafe { host.device.as_hal::<wgpu::hal::api::Vulkan>() }) else {
            return 5;
        };
        for index in 0..target.image_count as usize {
            let raw = unsafe { *target.images.add(index) };
            let hal_desc = wgpu::hal::TextureDescriptor {
                label: Some("ui-target"),
                size: wgpu::Extent3d {
                    width: target.width,
                    height: target.height,
                    depth_or_array_layers: 1,
                },
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format,
                usage: wgpu::TextureUses::COLOR_TARGET,
                memory_flags: wgpu::hal::MemoryFlags::empty(),
                view_formats: vec![],
            };
            let hal_texture = unsafe {
                hal.texture_from_raw(
                    vk::Image::from_raw(raw),
                    &hal_desc,
                    Some(Box::new(|| {})),
                    wgpu::hal::vulkan::TextureMemory::External,
                )
            };
            let desc = wgpu::TextureDescriptor {
                label: Some("ui-target"),
                size: hal_desc.size,
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format,
                usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
                view_formats: &[],
            };
            let texture = unsafe {
                host.device.create_texture_from_hal::<wgpu::hal::api::Vulkan>(
                    hal_texture,
                    &desc,
                    wgpu::TextureUses::COLOR_TARGET,
                )
            };
            views.push(texture.create_view(&wgpu::TextureViewDescriptor::default()));
            textures.push(texture);
        }
    }

    host.format = Some(format);
    host.width = target.width;
    host.height = target.height;
    host.renderer = Some(Renderer::new(&host.device, format));
    let scale = if target.scale > 0.0 { target.scale } else { 1.0 };
    let mut fx = FxRenderer::new(&host.device, format, FxOptions { dither: true });
    fx.add_format(&host.device, wgpu::TextureFormat::Rgba16Float);
    host.fx = Some(fx);
    host.scale = scale;
    let viewport = (target.width as f32 / scale, target.height as f32 / scale);
    if let Some(runtime) = host.runtime.as_mut() {
        // The target can be recreated on a resize; keep the view model, focus,
        // and text atlas instead of rebuilding the whole runtime.
        runtime.env.scale = scale;
        runtime.set_viewport(viewport, scale);
    } else {
        let text_system = TextSystem::new(&[GEIST, GEIST_MONO], ("Geist", "Geist Mono"));
        let mut runtime = Runtime::with_text(
            UiState::new(),
            views::view,
            viewport,
            Env::new(false, scale),
            text_system,
        );
        runtime.frame(0.0);
        runtime.settle_all();
        host.runtime = Some(runtime);
    }
    host.textures = textures;
    host.views = views;
    0
}

fn texture_format(value: u32) -> Option<wgpu::TextureFormat> {
    Some(match vk::Format::from_raw(value as i32) {
        vk::Format::R8G8B8A8_UNORM => wgpu::TextureFormat::Rgba8Unorm,
        vk::Format::R8G8B8A8_SRGB => wgpu::TextureFormat::Rgba8UnormSrgb,
        vk::Format::B8G8R8A8_UNORM => wgpu::TextureFormat::Bgra8Unorm,
        vk::Format::B8G8R8A8_SRGB => wgpu::TextureFormat::Bgra8UnormSrgb,
        _ => return None,
    })
}

pub fn host() -> Option<&'static mut Host> {
    // SAFETY: `HOST` only stores the pointer from `Box::leak` in `init_vk`.
    HOST.get().map(|&pointer| unsafe { &mut *(pointer as *mut Host) })
}
