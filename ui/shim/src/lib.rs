mod abi;
mod components;
mod fx;
mod host;
mod input;
mod paint;
mod state;
mod text;
mod theme;
mod views;

use std::ffi::c_char;

use abi::{
    UiAction, UiEvent, UiMenu, UiPalette, UiPanel, UiSnapshot, UiTarget, UiVkConfig, UiVkDevice,
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
    palette: *const UiPalette,
    events: *const UiEvent,
    count: u32,
) -> i32 {
    let Some(host) = host::host() else { return 1 };
    state::frame(host, dt, snapshot, panel, menu, palette, events, count)
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
    input::click_point(runtime, x, y)
}

#[unsafe(no_mangle)]
pub extern "C" fn ui_click_element(pointer: *const u8, len: u32) -> i32 {
    let Some(host) = host::host() else { return 1 };
    let Some(runtime) = host.runtime.as_mut() else { return 2 };
    let key = unsafe { abi::text_bytes(pointer, len) };
    input::click_element(runtime, &key)
}
