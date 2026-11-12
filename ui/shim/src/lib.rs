use std::ffi::{c_char, c_void};
use std::sync::OnceLock;

use ash::vk;
use ash::vk::Handle;
use rune::render::{EffectPhase, EffectSite, Renderer};
use rune::text::TextSystem;
use rune::{Cx, El, Env, Key, KeyEvent, Mods, Runtime, Span, text};
use rune_fx::{Fx, FxFrame, FxLayer, FxOptions, FxRenderer, FxSlot, GlowParams, Shape, rgb};

const GEIST: &[u8] = include_bytes!("../assets/Geist-Variable.ttf");
const GEIST_MONO: &[u8] = include_bytes!("../assets/GeistMono-Variable.ttf");
const ROW_NUMERIC: u32 = 1;
const ROW_BLOCKED: u32 = 2;

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
    ratio: f32,
}

#[derive(Default)]
struct MenuState {
    open: bool,
    title: String,
    rows: Vec<PanelRow>,
    selected: usize,
    note: String,
    hints: Vec<(String, String)>,
}

struct PaletteItem {
    name: String,
    short: String,
}

#[derive(Default)]
struct PaletteState {
    open: bool,
    title: String,
    items: Vec<PaletteItem>,
    selected: usize,
    body: String,
    hints: Vec<(String, String)>,
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
    fx: bool,
    weight: f32,
    actions: Vec<UiAction>,
    panel: PanelState,
    menu: MenuState,
    palette: PaletteState,
}

#[repr(C)]
pub struct UiSnapshot {
    pub speed: f32,
    pub grounded: u32,
    pub menu_open: u32,
    pub palette_open: u32,
    pub fx: u32,
    pub weight: f32,
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
    /// Reserved for the remaining UI port; the Rune view does not read it.
    pub ticks: u32,
}

#[repr(C)]
pub struct UiHint {
    pub keys: *const u8,
    pub keys_len: u32,
    pub action: *const u8,
    pub action_len: u32,
}

#[repr(C)]
pub struct UiMenu {
    pub open: u32,
    pub title: *const u8,
    pub title_len: u32,
    pub rows: *const UiRow,
    pub row_count: u32,
    pub selected: u32,
    pub note: *const u8,
    pub note_len: u32,
    pub hints: *const UiHint,
    pub hint_count: u32,
    pub hint_columns: u32,
}

#[repr(C)]
pub struct UiPaletteItem {
    pub name: *const u8,
    pub name_len: u32,
    pub short: *const u8,
    pub short_len: u32,
    /// Reserved for the remaining UI port; the Rune view does not read it.
    pub color: [f32; 4],
    /// Reserved for the remaining UI port; the Rune view does not read it.
    pub key: *const u8,
    pub key_len: u32,
}

#[repr(C)]
pub struct UiPalette {
    pub open: u32,
    pub title: *const u8,
    pub title_len: u32,
    pub items: *const UiPaletteItem,
    pub item_count: u32,
    pub selected: u32,
    pub body: *const u8,
    pub body_len: u32,
    /// Reserved for the remaining UI port; the Rune view does not read it.
    pub size: *const u8,
    pub size_len: u32,
    /// Reserved for the remaining UI port; the Rune view does not read it.
    pub count: *const u8,
    pub count_len: u32,
    pub hints: *const UiHint,
    pub hint_count: u32,
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
    fx: Option<FxRenderer>,
    textures: Vec<wgpu::Texture>,
    views: Vec<wgpu::TextureView>,
    width: u32,
    height: u32,
    scale: f32,
}

const FX_GLOW: u32 = 1;

static HOST: OnceLock<usize> = OnceLock::new();
static EXTENSIONS: OnceLock<Vec<usize>> = OnceLock::new();

fn instance_extensions() -> Result<&'static Vec<usize>, String> {
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

/// Adopt the game's Vulkan instance and physical device.
///
/// # Safety
///
/// `config` must point at a live Vulkan instance and physical device created by
/// the game. The queue families must be valid for that physical device, and the
/// game must not destroy the instance or device while the returned `Host` lives.
unsafe fn adopt(
    config: &UiVkConfig,
) -> Result<(UiVkDevice, Host), String> {
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
    let ash_instance =
        unsafe { ash::Instance::load(entry.static_fn(), raw_instance) };
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
    let instance =
        unsafe { wgpu::Instance::from_hal::<wgpu::hal::api::Vulkan>(hal_instance) };

    let raw_physical = vk::PhysicalDevice::from_raw(config.physical_device as u64);
    let adapters = pollster::block_on(instance.enumerate_adapters(wgpu::Backends::VULKAN));
    let adapter = adapters
        .into_iter()
        .find(|a| unsafe { a.as_hal::<wgpu::hal::api::Vulkan>() }
            .is_some_and(|h| h.raw_physical_device() == raw_physical))
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
    if config.present_family != u32::MAX
        && !extensions.contains(&ash::khr::swapchain::NAME)
    {
        extensions.push(ash::khr::swapchain::NAME);
    }
    let mut device_features =
        hal_adapter.physical_device_features(&extensions, features);

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

    // SAFETY: The caller guarantees the physical device and queue families; the
    // extensions and features came from this adapter; the HAL device owns the
    // returned raw device.
    let raw_device = unsafe {
        ash_instance.create_device(raw_physical, &create_info, None)
    }
    .map_err(|e| format!("vkCreateDevice: {e:?}"))?;
    let raw_device_handle = raw_device.handle();
    // SAFETY: The device was created with this queue family; index 0 is valid.
    let graphics_queue =
        unsafe { raw_device.get_device_queue(config.graphics_family, 0) };
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
    // SAFETY: `HOST` only stores the pointer from `Box::leak` in `ui_vk_init`.
    HOST.get().map(|&pointer| unsafe { &mut *(pointer as *mut Host) })
}

fn weighted_text(content: &str, weight: f32, mono: bool) -> El {
    let element = text(content);
    if weight <= 0.0 && !mono {
        return element;
    }
    let mut span = Span::new(0, content.len());
    if weight > 0.0 {
        span = span.weight(weight);
    }
    if mono {
        span = span.mono();
    }
    element.spans(vec![span])
}

fn view(state: &UiState, _: &mut Cx<UiState>) -> El {
    use rune::{Color, col, el, row, spacer};
    if state.menu_open || state.menu.open {
        return menu_view(state);
    }
    if state.palette.open {
        return palette_view(state);
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
            6 => panel.child(weighted_text(r.label.as_str(), state.weight, false).color(tertiary)),
            0 | 1 | 2 | 3 | 4 => {
                let label_color = if r.kind == 3 { tertiary } else { secondary };
                let value_color = if r.flags & ROW_BLOCKED != 0 { secondary } else { primary };
                let line = row()
                    .w_full()
                    .gap(12.0)
                    .child(weighted_text(r.label.as_str(), state.weight, false).color(label_color))
                    .child(spacer())
                    .child(weighted_text(
                        r.value.as_str(),
                        state.weight,
                        r.flags & ROW_NUMERIC != 0,
                    ).color(value_color));
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
        weighted_text(state.panel.capture_hint.as_str(), state.weight, false).color(primary)
    };
    let notice = if state.panel.notice.is_empty() {
        col()
    } else {
        weighted_text(state.panel.notice.as_str(), state.weight, false).color(primary)
    };

    let ink = Color { r: 0.04, g: 0.05, b: 0.07, a: 1.0 };
    let accent = Color { r: 0.90, g: 0.69, b: 0.23, a: 1.0 };
    let close = el()
        .key("action:1")
        .padding(8.0)
        .radius(6.0)
        .focusable(true)
        .focus_ring(2.0, 2.0, accent)
        .hover(Color { r: 1.0, g: 1.0, b: 1.0, a: 0.10 })
        .press(Color { r: 1.0, g: 1.0, b: 1.0, a: 0.18 })
        .fill(accent)
        .child(weighted_text("Close", state.weight, false).color(ink))
        .on_press(|s: &mut UiState| {
            s.actions.push(UiAction { kind: 1, value: 0 });
        });
    let debug = el()
        .key("action:2")
        .padding(8.0)
        .radius(6.0)
        .focusable(true)
        .focus_ring(2.0, 2.0, accent)
        .hover(Color { r: 1.0, g: 1.0, b: 1.0, a: 0.08 })
        .press(Color { r: 1.0, g: 1.0, b: 1.0, a: 0.14 })
        .fill(Color { r: 0.16, g: 0.19, b: 0.24, a: 1.0 })
        .child(weighted_text("Debug", state.weight, false).color(Color::WHITE))
        .on_press(|s: &mut UiState| {
            s.actions.push(UiAction { kind: 2, value: 0 });
        });

    let glow = rune::effect(FX_GLOW)
        .effect_data([0.9, 0.0, 0.0, 0.0])
        .effect_bleed(60.0)
        .opacity(0.85);
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
                .child({
                    let mut actions = row().gap(8.0);
                    if state.fx {
                        actions = actions.child(glow.absolute(0.0, 0.0).w_full().h_full());
                    }
                    actions.child(close).child(debug)
                }),
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
            UiState {
                speed: 0.0,
                grounded: false,
                menu_open: false,
                fx: false,
                weight: 0.0,
                actions: Vec::new(),
                panel: PanelState::default(),
                menu: MenuState::default(),
                palette: PaletteState::default(),
            },
            view,
            viewport,
            Env::new(false, scale),
            text_system,
        );
        runtime.frame(0.0);
        host.runtime = Some(runtime);
    }
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
    let plan = fx_plan(runtime);
    if let Some(fx) = host.fx.as_mut() {
        let _ = fx.prepare_with_slots(
            &host.device,
            &host.queue,
            &FxFrame {
                viewport: [host.width, host.height],
                scale: host.scale,
                layers: &plan.layers,
                backdrop: None,
                sources: &[],
            },
            &plan.slots,
        );
    }
    let fx = host.fx.as_ref();
    let mut encoder = host
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("rune-ui") });
    renderer.encode_layers_with(&mut encoder, &mut |pass, site| {
        if site.in_layer {
            if let Some(fx) = fx {
                draw_effect(fx, &plan.effects, pass, site);
            }
        }
    });
    renderer.draw_target_range_with(
        &mut encoder,
        &host.views[index],
        format,
        wgpu::LoadOp::Load,
        0..runtime.instances.len() as u32,
        &mut |phase, site| {
            if let EffectPhase::Draw(pass) = phase {
                if !site.in_layer {
                    if let Some(fx) = fx {
                        draw_effect(fx, &plan.effects, pass, site);
                    }
                }
            }
        },
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
    menu: *const UiMenu,
    palette: *const UiPalette,
    events: *const UiEvent,
    count: u32,
) -> i32 {
    let Some(host) = host() else { return 1 };
    let Some(snapshot) = (unsafe { snapshot.as_ref() }) else { return 2 };
    let Some(runtime) = host.runtime.as_mut() else { return 3 };

    runtime.state.speed = snapshot.speed;
    runtime.state.grounded = snapshot.grounded != 0;
    runtime.state.menu_open = snapshot.menu_open != 0;
    runtime.state.fx = snapshot.fx != 0;
    runtime.state.weight = snapshot.weight;

    if let Some(panel) = unsafe { panel.as_ref() } {
        // SAFETY: The FFI caller owns the row array for this call.
        let rows = unsafe { panel_rows(panel.rows, panel.row_count) };
        runtime.state.panel = PanelState {
            rows,
            notice: unsafe { text_bytes(panel.notice, panel.notice_len) },
            capture_hint: unsafe {
                text_bytes(panel.capture_hint, panel.capture_hint_len)
            },
            captured: panel.captured != 0,
            palette_open: panel.palette_open != 0,
        };
    }

    if let Some(menu) = unsafe { menu.as_ref() } {
        // SAFETY: The FFI caller owns the row array for this call.
        let rows = unsafe { panel_rows(menu.rows, menu.row_count) };
        let mut hints = Vec::with_capacity(menu.hint_count as usize);
        if !menu.hints.is_null() {
            for index in 0..menu.hint_count as usize {
                let hint = unsafe { &*menu.hints.add(index) };
                hints.push((
                    unsafe { text_bytes(hint.keys, hint.keys_len) },
                    unsafe { text_bytes(hint.action, hint.action_len) },
                ));
            }
        }
        runtime.state.menu = MenuState {
            open: menu.open != 0,
            title: unsafe { text_bytes(menu.title, menu.title_len) },
            rows,
            selected: menu.selected as usize,
            note: unsafe { text_bytes(menu.note, menu.note_len) },
            hints,
        };
    }

    if let Some(palette) = unsafe { palette.as_ref() } {
        let mut items = Vec::with_capacity(palette.item_count as usize);
        if !palette.items.is_null() {
            for index in 0..palette.item_count as usize {
                let item = unsafe { &*palette.items.add(index) };
                items.push(PaletteItem {
                    name: unsafe { text_bytes(item.name, item.name_len) },
                    short: unsafe { text_bytes(item.short, item.short_len) },
                });
            }
        }
        let mut hints = Vec::with_capacity(palette.hint_count as usize);
        if !palette.hints.is_null() {
            for index in 0..palette.hint_count as usize {
                let hint = unsafe { &*palette.hints.add(index) };
                hints.push((
                    unsafe { text_bytes(hint.keys, hint.keys_len) },
                    unsafe { text_bytes(hint.action, hint.action_len) },
                ));
            }
        }
        runtime.state.palette = PaletteState {
            open: palette.open != 0,
            title: unsafe { text_bytes(palette.title, palette.title_len) },
            items,
            selected: palette.selected as usize,
            body: unsafe { text_bytes(palette.body, palette.body_len) },
            hints,
        };
    }

    if !events.is_null() {
        for index in 0..count as usize {
            let event = unsafe { &*events.add(index) };
            match event.kind {
                UI_EVENT_POINTER_MOVE => runtime.pointer_move(event.x, event.y),
                UI_EVENT_POINTER_DOWN => runtime.pointer_down(event.x, event.y),
                UI_EVENT_POINTER_UP => runtime.pointer_up(event.x, event.y),
                UI_EVENT_POINTER_LEAVE => runtime.pointer_leave(),
                UI_EVENT_WHEEL => runtime.wheel(event.x, event.y, -event.dy * 40.0),
                UI_EVENT_KEY_DOWN => {
                    if let Some(key) = key_from_code(event.key) {
                        runtime.key(KeyEvent { key, mods: Mods::default() });
                    }
                }
                UI_EVENT_KEY_UP => {
                    if let Some(key) = key_from_code(event.key) {
                        runtime.key_up(KeyEvent { key, mods: Mods::default() });
                    }
                }
                UI_EVENT_KEY_REPEAT => {
                    if let Some(key) = key_from_code(event.key) {
                        runtime.repeat_key(KeyEvent { key, mods: Mods::default() });
                    }
                }
                UI_EVENT_FOCUS => runtime.window_focus(event.flags & 1 != 0),
                _ => {}
            }
        }
    }
    runtime.invalidate();
    runtime.frame(dt);
    0
}

const UI_EVENT_POINTER_MOVE: u32 = 1;
const UI_EVENT_POINTER_DOWN: u32 = 2;
const UI_EVENT_POINTER_UP: u32 = 3;
const UI_EVENT_POINTER_LEAVE: u32 = 4;
const UI_EVENT_WHEEL: u32 = 7;
const UI_EVENT_KEY_DOWN: u32 = 8;
const UI_EVENT_KEY_UP: u32 = 9;
const UI_EVENT_KEY_REPEAT: u32 = 10;
const UI_EVENT_FOCUS: u32 = 11;

fn key_from_code(code: i32) -> Option<Key> {
    Some(match code {
        1 => Key::Up,
        2 => Key::Down,
        3 => Key::Left,
        4 => Key::Right,
        5 => Key::Enter,
        6 => Key::Escape,
        7 => Key::Tab,
        _ => return None,
    })
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

#[unsafe(no_mangle)]
pub extern "C" fn ui_click_point(x: f32, y: f32) -> i32 {
    let Some(host) = host() else { return 1 };
    let Some(runtime) = host.runtime.as_mut() else { return 2 };
    click_runtime(runtime, x, y);
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_click_element(pointer: *const u8, len: u32) -> i32 {
    let Some(host) = host() else { return 1 };
    let Some(runtime) = host.runtime.as_mut() else { return 2 };
    let key = unsafe { text_bytes(pointer, len) };
    let Some((x, y)) = runtime.find(&key) else { return 3 };
    click_runtime(runtime, x, y);
    0
}

fn click_runtime(runtime: &mut Runtime<UiState>, x: f32, y: f32) {
    runtime.pointer_move(x, y);
    runtime.pointer_down(x, y);
    runtime.pointer_up(x, y);
    runtime.invalidate();
    runtime.frame(0.0);
}

fn menu_view(state: &UiState) -> El {
    menu_panel(&state.menu, None, state.weight)
}

fn menu_panel(menu: &MenuState, key_prefix: Option<&str>, weight: f32) -> El {
    use rune::{Color, col, el, row, spacer};
    let scrim = Color { r: 0.0, g: 0.0, b: 0.0, a: 0.62 };
    let surface = Color { r: 0.08, g: 0.10, b: 0.13, a: 1.0 };
    let raised = Color { r: 0.15, g: 0.19, b: 0.24, a: 1.0 };
    let hairline = Color { r: 0.35, g: 0.38, b: 0.42, a: 0.25 };
    let primary = Color { r: 0.93, g: 0.95, b: 0.97, a: 1.0 };
    let secondary = Color { r: 0.65, g: 0.70, b: 0.75, a: 1.0 };
    let tertiary = Color { r: 0.50, g: 0.55, b: 0.60, a: 1.0 };
    let accent = Color { r: 0.90, g: 0.69, b: 0.23, a: 1.0 };

    let mut panel = col()
        .w(430.0)
        .padding(16.0)
        .gap(8.0)
        .fill(surface)
        .on_press(|_: &mut UiState| {});
    panel = panel
        .child(
            row()
                .w_full()
                .child(spacer())
                .child(weighted_text(menu.title.as_str(), weight, false).color(primary))
                .child(spacer()),
        )
        .child(el().h(1.0).w_full().fill(hairline));

    for (index, r) in menu.rows.iter().enumerate() {
        if r.kind == 5 {
            panel = panel.child(el().h(1.0).w_full().fill(hairline));
            continue;
        }
        if r.kind == 6 {
            panel = panel.child(weighted_text(r.label.as_str(), weight, false).color(tertiary));
            continue;
        }
        let selected = index == menu.selected;
        let label_color = if selected { primary } else { secondary };
        let mut line = row()
            .w_full()
            .padding(4.0)
            .gap(12.0)
            .fill(if selected { raised } else { Color::TRANSPARENT })
            .child(if selected { el().w(2.0).h(18.0).fill(accent) } else { el() })
            .child(weighted_text(r.label.as_str(), weight, false).color(label_color))
            .child(spacer())
            .child(weighted_text(
                r.value.as_str(),
                weight,
                r.flags & ROW_NUMERIC != 0,
            ).color(primary));
        if let Some(prefix) = key_prefix {
            let index_value = index as i32;
            line = line
                .key(format!("{prefix}{index}"))
                .hover(Color { r: 1.0, g: 1.0, b: 1.0, a: 0.06 })
                .press(Color { r: 1.0, g: 1.0, b: 1.0, a: 0.10 })
                .on_press(move |s: &mut UiState| {
                    s.actions.push(UiAction { kind: 3, value: index_value });
                });
        }
        panel = panel.child(line);
        if r.kind == 4 {
            let track = el()
                .w_full()
                .h(4.0)
                .fill(Color { r: 1.0, g: 1.0, b: 1.0, a: 0.20 })
                .child(el().w(r.ratio * 390.0).h_full().fill(accent));
            panel = panel.child(track);
        }
    }

    let note = if menu.note.is_empty() {
        col()
    } else {
        weighted_text(menu.note.as_str(), weight, false).color(tertiary)
    };
    panel = panel.child(note);

    let mut hints = col().w_full().gap(4.0);
    let per_row = 3usize;
    for chunk in menu.hints.chunks(per_row) {
        let mut line = row().gap(16.0);
        for (keys, action) in chunk {
            line = line
                .child(weighted_text(keys.as_str(), weight, false).color(primary))
                .child(weighted_text(action.as_str(), weight, false).color(secondary));
        }
        hints = hints.child(line);
    }
    panel = panel.child(hints);

    let scrim_action: u32 = if key_prefix.is_some() { 4 } else { 1 };
    col()
        .w_full()
        .h_full()
        .items_center()
        .justify_center()
        .child(
            el()
                .absolute(0.0, 0.0)
                .w_full()
                .h_full()
                .fill(scrim)
                .on_press(move |s: &mut UiState| {
                    s.actions.push(UiAction { kind: scrim_action, value: 0 });
                }),
        )
        .child(panel)
}

fn palette_view(state: &UiState) -> El {
    let rows: Vec<PanelRow> = state
        .palette
        .items
        .iter()
        .map(|item| PanelRow {
            kind: 0,
            flags: 0,
            label: item.short.clone(),
            value: item.name.clone(),
            ratio: 0.0,
        })
        .collect();
    let menu = MenuState {
        open: true,
        title: state.palette.title.clone(),
        rows,
        selected: state.palette.selected,
        note: state.palette.body.clone(),
        hints: state.palette.hints.clone(),
    };
    menu_panel(&menu, Some("palette:"), state.weight)
}

struct FxSlotPlan {
    instance: u32,
    layer: usize,
}

struct FxPlan {
    layers: Vec<FxLayer>,
    slots: Vec<FxSlot>,
    effects: Vec<FxSlotPlan>,
}

fn fx_plan(runtime: &Runtime<UiState>) -> FxPlan {
    // Layers and slots upload before the pass; the hook can only draw them.
    let mut layers = Vec::new();
    let mut slots = Vec::new();
    let mut plans = Vec::new();
    for (index, instance) in runtime.instances.iter().enumerate() {
        if instance.params[1] != rune::render::KIND_EFFECT {
            continue;
        }
        let mark = instance.border[0] as u32 | ((instance.border[1] as u32) << 16);
        if mark != FX_GLOW {
            continue;
        }
        let k = instance.params[3];
        let [x, y, w, h] = instance.rect;
        let fx = Fx::glow(GlowParams {
            color: rgb(0x7C5CFF),
            core: rgb(0xF4F0FF),
            intensity: instance.uv[0].clamp(0.0, 3.0),
            radius: 12.0,
            ..Default::default()
        });
        layers.push(fx.on(Shape::rounded(x / k, y / k, w / k, h / k, 0.0)));
        slots.push(FxSlot::default().scale(k).clip(instance.clip, instance.fade));
        plans.push(FxSlotPlan {
            instance: index as u32,
            layer: layers.len() - 1,
        });
    }
    FxPlan { layers, slots, effects: plans }
}

fn draw_effect(
    fx: &FxRenderer,
    plans: &[FxSlotPlan],
    pass: &mut wgpu::RenderPass<'_>,
    site: &EffectSite<'_>,
) {
    if site.mark != FX_GLOW {
        return;
    }
    let Some(plan) = plans.iter().find(|plan| plan.instance == site.index) else {
        return;
    };
    if site.in_layer {
        fx.draw_layer_in(pass, site.format, site.origin, plan.layer);
    } else {
        fx.draw_layer(pass, plan.layer);
    }
}

/// # Safety
///
/// `pointer` must point to `len` readable bytes that stay valid for the call,
/// or be null with any length.
unsafe fn text_bytes(pointer: *const u8, len: u32) -> String {
    if pointer.is_null() || len == 0 {
        return String::new();
    }
    // SAFETY: The caller guarantees the pointer and length; the null and zero
    // checks above cover the empty slice.
    String::from_utf8_lossy(unsafe { std::slice::from_raw_parts(pointer, len as usize) })
        .into_owned()
}

/// # Safety
///
/// `rows` must point to `count` valid `UiRow` values whose label and value
/// pointers are readable for their lengths or null, or be null.
unsafe fn panel_rows(rows: *const UiRow, count: u32) -> Vec<PanelRow> {
    if rows.is_null() {
        return Vec::new();
    }
    (0..count as usize)
        .map(|index| {
            // SAFETY: The caller guarantees the pointer and count.
            let row = unsafe { &*rows.add(index) };
            PanelRow {
                kind: row.kind,
                flags: row.flags,
                label: unsafe { text_bytes(row.label, row.label_len) },
                value: unsafe { text_bytes(row.value, row.value_len) },
                ratio: row.ratio,
            }
        })
        .collect()
}
