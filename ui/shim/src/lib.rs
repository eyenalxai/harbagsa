use std::ffi::{c_char, c_void};
use std::sync::OnceLock;

use ash::vk;
use ash::vk::Handle;
use rune::render::Renderer;
use rune::{Cx, El, Env, Key, KeyEvent, Mods, Runtime};

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

#[derive(Default)]
struct PanelRow {
    kind: u32,
    flags: u32,
    label: String,
    value: String,
}

#[derive(Default)]
struct PanelState {
    rows: Vec<PanelRow>,
    notice: String,
    capture_hint: String,
    captured: bool,
    palette_open: bool,
}

struct UiState {
    speed: f32,
    grounded: bool,
    menu_open: bool,
    actions: Vec<UiAction>,
    panel: PanelState,
}

#[repr(C)]
pub struct UiSnapshot {
    pub speed: f32,
    pub grounded: u32,
    pub menu_open: u32,
    pub palette_open: u32,
}

#[repr(C)]
pub struct UiRow {
    pub kind: u32,
    pub flags: u32,
    pub label: *const u8,
    pub label_len: u32,
    pub value: *const u8,
    pub value_len: u32,
    pub ratio: f32,
    pub ticks: u32,
}

#[repr(C)]
pub struct UiPanel {
    pub rows: *const UiRow,
    pub row_count: u32,
    pub notice: *const u8,
    pub notice_len: u32,
    pub capture_hint: *const u8,
    pub capture_hint_len: u32,
    pub captured: u32,
    pub palette_open: u32,
}

#[repr(C)]
pub struct UiEvent {
    pub kind: u32,
    pub flags: u32,
    pub x: f32,
    pub y: f32,
    pub dx: f32,
    pub dy: f32,
    pub key: i32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct UiAction {
    pub kind: u32,
    pub value: i32,
}

#[repr(C)]
pub struct UiTarget {
    pub format: u32,
    pub width: u32,
    pub height: u32,
    pub scale: f32,
    pub images: *const u64,
    pub image_count: u32,
}

struct Host {
    _instance: wgpu::Instance,
    device: wgpu::Device,
    queue: wgpu::Queue,
    format: Option<wgpu::TextureFormat>,
    runtime: Option<Runtime<UiState>>,
    renderer: Option<Renderer>,
    textures: Vec<wgpu::Texture>,
    views: Vec<wgpu::TextureView>,
    width: u32,
    height: u32,
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
            device,
            queue,
            format: None,
            runtime: None,
            renderer: None,
            textures: Vec::new(),
            views: Vec::new(),
            width: 0,
            height: 0,
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

fn texture_format(value: u32) -> Option<wgpu::TextureFormat> {
    Some(match vk::Format::from_raw(value as i32) {
        vk::Format::R8G8B8A8_UNORM => wgpu::TextureFormat::Rgba8Unorm,
        vk::Format::R8G8B8A8_SRGB => wgpu::TextureFormat::Rgba8UnormSrgb,
        vk::Format::B8G8R8A8_UNORM => wgpu::TextureFormat::Bgra8Unorm,
        vk::Format::B8G8R8A8_SRGB => wgpu::TextureFormat::Bgra8UnormSrgb,
        _ => return None,
    })
}

fn host() -> Option<&'static mut Host> {
    HOST.get().map(|&pointer| unsafe { &mut *(pointer as *mut Host) })
}

fn view(state: &UiState, _: &mut Cx<UiState>) -> El {
    use rune::{Color, col, el, row, spacer, text};
    if state.menu_open {
        return col();
    }
    let surface = Color { r: 0.06, g: 0.08, b: 0.10, a: 0.94 };
    let hairline = Color { r: 0.35, g: 0.38, b: 0.42, a: 0.25 };
    let primary = Color { r: 0.93, g: 0.95, b: 0.97, a: 1.0 };
    let secondary = Color { r: 0.65, g: 0.70, b: 0.75, a: 1.0 };
    let tertiary = Color { r: 0.50, g: 0.55, b: 0.60, a: 1.0 };

    let mut panel = col()
        .absolute(12.0, 12.0)
        .w(380.0)
        .padding(12.0)
        .gap(6.0)
        .fill(surface);
    for r in &state.panel.rows {
        panel = match r.kind {
            5 => panel.child(el().h(1.0).w_full().fill(hairline)),
            6 => panel.child(text(r.label.as_str()).color(tertiary)),
            0 | 1 | 2 | 3 | 4 => {
                let label_color = if r.kind == 3 { tertiary } else { secondary };
                let value_color = if r.flags & 2 != 0 { secondary } else { primary };
                let line = row()
                    .w_full()
                    .gap(12.0)
                    .child(text(r.label.as_str()).color(label_color))
                    .child(spacer())
                    .child(text(r.value.as_str()).color(value_color));
                panel.child(line)
            }
            _ => panel,
        };
    }

    let hint = if state.panel.capture_hint.is_empty()
        || state.panel.captured
        || state.panel.palette_open
    {
        col()
    } else {
        text(state.panel.capture_hint.as_str()).color(primary)
    };
    let notice = if state.panel.notice.is_empty() {
        col()
    } else {
        text(state.panel.notice.as_str()).color(primary)
    };

    let ink = Color { r: 0.04, g: 0.05, b: 0.07, a: 1.0 };
    let accent = Color { r: 0.90, g: 0.69, b: 0.23, a: 1.0 };
    let close = el()
        .padding(8.0)
        .radius(6.0)
        .fill(accent)
        .child(text("Close").color(ink))
        .on_press(|s: &mut UiState| {
            s.actions.push(UiAction { kind: 1, value: 0 });
        });
    let debug = el()
        .padding(8.0)
        .radius(6.0)
        .fill(Color { r: 0.16, g: 0.19, b: 0.24, a: 1.0 })
        .child(text("Debug").color(Color::WHITE))
        .on_press(|s: &mut UiState| {
            s.actions.push(UiAction { kind: 2, value: 0 });
        });

    col()
        .w_full()
        .h_full()
        .child(panel)
        .child(
            col()
                .w_full()
                .h_full()
                .justify_end()
                .items_center()
                .padding(16.0)
                .gap(8.0)
                .child(notice)
                .child(hint)
                .child(row().gap(8.0).child(close).child(debug)),
        )
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_attach(target: *const UiTarget) -> i32 {
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
    let mut runtime = Runtime::new(
        UiState {
            speed: 0.0,
            grounded: false,
            menu_open: false,
            actions: Vec::new(),
            panel: PanelState::default(),
        },
        view,
        (target.width as f32 / scale, target.height as f32 / scale),
        Env::new(false, scale),
    );
    runtime.frame(0.0);
    host.runtime = Some(runtime);
    host.textures = textures;
    host.views = views;
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_draw(image_index: u32) -> i32 {
    let Some(host) = host() else { return 1 };
    let index = image_index as usize;
    if index >= host.views.len() {
        return 2;
    }
    let Some(format) = host.format else { return 3 };
    let Some(runtime) = host.runtime.as_mut() else { return 4 };
    let Some(renderer) = host.renderer.as_mut() else { return 5 };

    renderer.prepare(
        &host.device,
        &host.queue,
        &mut runtime.text.atlas,
        &runtime.instances,
        (host.width, host.height),
    );
    let mut encoder = host
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("rune-ui") });
    renderer.encode_layers(&mut encoder);
    renderer.draw_target_range_with(
        &mut encoder,
        &host.views[index],
        format,
        wgpu::LoadOp::Load,
        0..runtime.instances.len() as u32,
        &mut |_, _| {},
    );
    let submission = renderer.submit(&host.queue, encoder);
    if host
        .device
        .poll(wgpu::PollType::Wait {
            submission_index: Some(submission),
            timeout: None,
        })
        .is_err()
    {
        return 6;
    }
    0
}


#[unsafe(no_mangle)]
pub extern "C" fn ui_frame(
    dt: f64,
    snapshot: *const UiSnapshot,
    panel: *const UiPanel,
    events: *const UiEvent,
    count: u32,
) -> i32 {
    let Some(host) = host() else { return 1 };
    let Some(snapshot) = (unsafe { snapshot.as_ref() }) else { return 2 };
    let Some(runtime) = host.runtime.as_mut() else { return 3 };

    runtime.state.speed = snapshot.speed;
    runtime.state.grounded = snapshot.grounded != 0;
    runtime.state.menu_open = snapshot.menu_open != 0;
    runtime.state.actions.clear();

    if let Some(panel) = unsafe { panel.as_ref() } {
        let mut rows = Vec::with_capacity(panel.row_count as usize);
        if !panel.rows.is_null() {
            for index in 0..panel.row_count as usize {
                let row = unsafe { &*panel.rows.add(index) };
                rows.push(PanelRow {
                    kind: row.kind,
                    flags: row.flags,
                    label: text_bytes(row.label, row.label_len),
                    value: text_bytes(row.value, row.value_len),
                });
            }
        }
        runtime.state.panel = PanelState {
            rows,
            notice: text_bytes(panel.notice, panel.notice_len),
            capture_hint: text_bytes(panel.capture_hint, panel.capture_hint_len),
            captured: panel.captured != 0,
            palette_open: panel.palette_open != 0,
        };
    }

    if !events.is_null() {
        for index in 0..count as usize {
            let event = unsafe { &*events.add(index) };
            match event.kind {
                1 => runtime.pointer_move(event.x, event.y),
                2 => runtime.pointer_down(event.x, event.y),
                3 => runtime.pointer_up(event.x, event.y),
                4 => runtime.wheel_xy(event.x, event.y, event.dx, event.dy),
                5 => {
                    let key = match event.key {
                        0 => Key::Enter,
                        1 => Key::Escape,
                        2 => Key::Up,
                        3 => Key::Down,
                        4 => Key::Left,
                        5 => Key::Right,
                        6 => Key::Tab,
                        _ => continue,
                    };
                    runtime.key(KeyEvent { key, mods: Mods::default() });
                }
                _ => {}
            }
        }
    }
    runtime.frame(dt);
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_actions(count: *mut u32) -> *const UiAction {
    let Some(host) = host() else { return std::ptr::null() };
    let Some(runtime) = host.runtime.as_ref() else { return std::ptr::null() };
    if !count.is_null() {
        unsafe { *count = runtime.state.actions.len() as u32 };
    }
    runtime.state.actions.as_ptr()
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_actions_clear() {
    if let Some(host) = host()
        && let Some(runtime) = host.runtime.as_mut()
    {
        runtime.state.actions.clear();
    }
}

fn text_bytes(pointer: *const u8, len: u32) -> String {
    if pointer.is_null() || len == 0 {
        return String::new();
    }
    String::from_utf8_lossy(unsafe { std::slice::from_raw_parts(pointer, len as usize) })
        .into_owned()
}
