mod abi;
mod components;
mod fx;
mod host;
mod input;
mod inspector;
mod introspect;
mod paint;
mod palette;
mod settings;
mod slider;
mod state;
mod text;
mod theme;
mod views;

use std::ffi::c_char;
use std::sync::{Mutex, OnceLock};

use abi::{
    UiAction, UiEvent, UiInspector, UiInteraction, UiMenu, UiPalette, UiPanel, UiSettings,
    UiSnapshot, UiTarget, UiVkConfig, UiVkDevice,
};

#[unsafe(no_mangle)]
pub extern "C" fn ui_vk_instance_extensions(count: *mut u32) -> *const *const c_char {
    let Ok(list) = host::instance_extensions() else {
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

#[unsafe(no_mangle)]
pub extern "C" fn ui_vk_init(config: *const UiVkConfig, out: *mut UiVkDevice) -> i32 {
    host::init_vk(config, out)
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_attach(target: *const UiTarget) -> i32 {
    host::attach(target)
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_draw(image_index: u32) -> i32 {
    let Some(host) = host::host() else { return 1 };
    paint::draw(host, image_index)
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_frame(
    dt: f64,
    snapshot: *const UiSnapshot,
    panel: *const UiPanel,
    menu: *const UiMenu,
    settings: *const UiSettings,
    palette: *const UiPalette,
    inspector: *const UiInspector,
    events: *const UiEvent,
    count: u32,
) -> i32 {
    let Some(host) = host::host() else { return 1 };
    state::frame(
        host, dt, snapshot, panel, menu, settings, palette, inspector, events, count,
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_actions(count: *mut u32) -> *const UiAction {
    let Some(host) = host::host() else { return std::ptr::null() };
    let Some(runtime) = host.runtime.as_ref() else { return std::ptr::null() };
    if !count.is_null() {
        unsafe { *count = runtime.state.actions.len() as u32 };
    }
    runtime.state.actions.as_ptr()
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_actions_clear() {
    if let Some(host) = host::host()
        && let Some(runtime) = host.runtime.as_mut()
    {
        runtime.state.actions.clear();
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_click_point(x: f32, y: f32) -> i32 {
    let Some(host) = host::host() else { return 1 };
    let Some(runtime) = host.runtime.as_mut() else { return 2 };
    input::click_point(runtime, x, y);
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_element_center(
    pointer: *const u8,
    len: u32,
    x: *mut f32,
    y: *mut f32,
) -> i32 {
    let Some(host) = host::host() else { return 1 };
    let Some(runtime) = host.runtime.as_ref() else { return 2 };
    let key = unsafe { abi::text_bytes(pointer, len) };
    let Some((center_x, center_y)) = introspect::element_center(runtime, &key) else {
        return 3;
    };
    if !x.is_null() {
        unsafe { *x = center_x };
    }
    if !y.is_null() {
        unsafe { *y = center_y };
    }
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_drag_at(
    x: f32,
    y: f32,
    dx: f32,
    dy: f32,
    steps: u32,
    hold: u32,
    cancel: u32,
) -> i32 {
    let Some(host) = host::host() else { return 1 };
    let Some(runtime) = host.runtime.as_mut() else { return 2 };
    input::drag_point(runtime, x, y, dx, dy, steps, hold != 0, cancel != 0, None);
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_drag_element(
    pointer: *const u8,
    len: u32,
    dx: f32,
    dy: f32,
    steps: u32,
    hold: u32,
    cancel: u32,
) -> i32 {
    let Some(host) = host::host() else { return 1 };
    let Some(runtime) = host.runtime.as_mut() else { return 2 };
    let key = unsafe { abi::text_bytes(pointer, len) };
    input::drag_element(runtime, &key, dx, dy, steps, hold != 0, cancel != 0)
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_wheel_at(x: f32, y: f32, dx: f32, dy: f32) -> i32 {
    let Some(host) = host::host() else { return 1 };
    let Some(runtime) = host.runtime.as_mut() else { return 2 };
    input::wheel_point(runtime, x, y, dx, dy);
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_wheel_element(
    pointer: *const u8,
    len: u32,
    dx: f32,
    dy: f32,
) -> i32 {
    let Some(host) = host::host() else { return 1 };
    let Some(runtime) = host.runtime.as_mut() else { return 2 };
    let key = unsafe { abi::text_bytes(pointer, len) };
    input::wheel_element(runtime, &key, dx, dy)
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_focus(focused: u32) -> i32 {
    let Some(host) = host::host() else { return 1 };
    let Some(runtime) = host.runtime.as_mut() else { return 2 };
    input::focus(runtime, focused != 0);
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_interaction(out: *mut UiInteraction) -> i32 {
    if out.is_null() {
        return 1;
    }
    let Some(host) = host::host() else { return 2 };
    let Some(runtime) = host.runtime.as_mut() else { return 3 };
    let mut interaction = introspect::Interaction::default();
    introspect::interaction(runtime, &mut interaction);
    let out = unsafe { &mut *out };
    write_key(&mut out.focus, &mut out.focus_len, interaction.focus.as_deref());
    write_key(&mut out.hover, &mut out.hover_len, interaction.hover.as_deref());
    write_key(
        &mut out.pressed,
        &mut out.pressed_len,
        interaction.pressed.as_deref(),
    );
    out.scroll_offset = interaction.scroll_offset;
    out.scroll_max = interaction.scroll_max;
    0
}

static TREE: OnceLock<Mutex<Vec<u8>>> = OnceLock::new();

#[unsafe(no_mangle)]
pub extern "C" fn ui_tree_json(len: *mut u32) -> *const u8 {
    let Some(host) = host::host() else { return std::ptr::null() };
    let Some(runtime) = host.runtime.as_ref() else { return std::ptr::null() };
    let text = introspect::tree_json(runtime);
    let buffer = TREE.get_or_init(|| Mutex::new(Vec::new()));
    let Ok(mut guard) = buffer.lock() else { return std::ptr::null() };
    guard.clear();
    guard.extend_from_slice(text.as_bytes());
    if !len.is_null() {
        unsafe { *len = guard.len() as u32 };
    }
    guard.as_ptr()
}

fn write_key(bytes: &mut [u8; abi::INTERACTION_KEY_BYTES], len: &mut u32, value: Option<&str>) {
    *len = 0;
    let Some(value) = value else { return };
    let source = value.as_bytes();
    let count = source.len().min(bytes.len());
    bytes[..count].copy_from_slice(&source[..count]);
    *len = count as u32;
}
