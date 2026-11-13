//! The flat C ABI. A few payload fields exist for the game snapshot and have no
//! view consumer yet.
#![allow(dead_code)]

use std::ffi::c_void;

use crate::state::{MenuState, PaletteItem, PaletteState, PanelRow, PanelState, SettingsState};

pub const ACTION_CLOSE_MENU: u32 = 1;
pub const ACTION_TOGGLE_DEBUG: u32 = 2;
pub const ACTION_PALETTE_SELECT: u32 = 3;
pub const ACTION_PALETTE_CLOSE: u32 = 4;
pub const ACTION_SETTINGS_SET: u32 = 5;
pub const ACTION_TYPE_WEIGHT_SET: u32 = 6;
pub const ACTION_PALETTE_PICK: u32 = 7;
pub const ACTION_OBJECT_SET: u32 = 8;
pub const ACTION_OBJECT_TOGGLE: u32 = 9;
pub const ACTION_OBJECT_DUPLICATE: u32 = 10;
pub const ACTION_OBJECT_DELETE: u32 = 11;
pub const ACTION_LAMP_SET: u32 = 12;
pub const ACTION_LAMP_KIND: u32 = 13;
pub const ACTION_LAMP_COLOR: u32 = 14;
pub const ACTION_TOGGLE_INSPECTOR: u32 = 15;

pub const SETTING_WINDOW_MODE: u32 = 0;
pub const SETTING_DISPLAY: u32 = 1;
pub const SETTING_RESOLUTION: u32 = 2;
pub const SETTING_SPRINT_MODE: u32 = 3;
pub const SETTING_HUD_OPACITY: u32 = 4;
pub const SETTING_REDUCE_MOTION: u32 = 5;

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
    pub note: *const u8,
    pub note_len: u32,
    pub hints: *const UiHint,
    pub hint_count: u32,
}

#[repr(C)]
pub struct UiOption {
    pub text: *const u8,
    pub text_len: u32,
}

#[repr(C)]
pub struct UiSettings {
    pub window_mode: u32,
    pub display: u32,
    pub resolution: i32,
    pub sprint_mode: u32,
    pub hud_opacity: f32,
    pub reduce_motion: u32,
    pub window_modes: *const UiOption,
    pub window_mode_count: u32,
    pub displays: *const UiOption,
    pub display_count: u32,
    pub resolutions: *const UiOption,
    pub resolution_count: u32,
    pub resolution_current: UiOption,
    pub resolution_missing: u32,
    pub sprint_modes: *const UiOption,
    pub sprint_mode_count: u32,
}

#[repr(C)]
pub struct UiPaletteItem {
    pub name: *const u8,
    pub name_len: u32,
    pub short: *const u8,
    pub short_len: u32,
    pub half_extents: [f32; 3],
    pub color: [f32; 4],
    pub base_pitch: f32,
    pub body: *const u8,
    pub body_len: u32,
    pub key: *const u8,
    pub key_len: u32,
    pub light_line: *const u8,
    pub light_line_len: u32,
    pub emissive: u32,
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
    pub size: *const u8,
    pub size_len: u32,
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
    pub id: u32,
    pub value: i32,
    pub scalar: f32,
}

impl UiAction {
    pub const fn new(kind: u32) -> Self {
        Self { kind, id: 0, value: 0, scalar: 0.0 }
    }

    pub const fn with_id(kind: u32, id: u32) -> Self {
        Self { kind, id, value: 0, scalar: 0.0 }
    }

    pub const fn with_value(kind: u32, value: i32) -> Self {
        Self { kind, id: 0, value, scalar: 0.0 }
    }
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

/// # Safety
///
/// `pointer` must point to `len` readable bytes that stay valid for the call,
/// or be null with any length.
pub unsafe fn text_bytes(pointer: *const u8, len: u32) -> String {
    if pointer.is_null() || len == 0 {
        return String::new();
    }
    String::from_utf8_lossy(unsafe { std::slice::from_raw_parts(pointer, len as usize) })
        .into_owned()
}

/// # Safety
///
/// `rows` must point to `count` valid `UiRow` values whose label and value
/// pointers are readable for their lengths or null, or be null.
unsafe fn rows(rows: *const UiRow, count: u32) -> Vec<PanelRow> {
    if rows.is_null() {
        return Vec::new();
    }
    (0..count as usize)
        .map(|index| {
            let row = unsafe { &*rows.add(index) };
            PanelRow {
                kind: row.kind,
                flags: row.flags,
                label: unsafe { text_bytes(row.label, row.label_len) },
                value: unsafe { text_bytes(row.value, row.value_len) },
            }
        })
        .collect()
}

/// # Safety
///
/// `hints` must point to `count` valid `UiHint` values whose key and action
/// pointers are readable for their lengths or null, or be null.
unsafe fn hints(hints: *const UiHint, count: u32) -> Vec<(String, String)> {
    if hints.is_null() {
        return Vec::new();
    }
    (0..count as usize)
        .map(|index| {
            let hint = unsafe { &*hints.add(index) };
            (
                unsafe { text_bytes(hint.keys, hint.keys_len) },
                unsafe { text_bytes(hint.action, hint.action_len) },
            )
        })
        .collect()
}

/// # Safety
///
/// `settings` must point to a valid `UiSettings` whose option pointers are
/// readable for their lengths or null, or be null.
pub unsafe fn settings_state(settings: *const UiSettings) -> Option<SettingsState> {
    let settings = unsafe { settings.as_ref() }?;
    let options = |ptr: *const UiOption, count: u32| -> Vec<String> {
        if ptr.is_null() {
            return Vec::new();
        }
        (0..count as usize)
            .map(|index| {
                let option = unsafe { &*ptr.add(index) };
                unsafe { text_bytes(option.text, option.text_len) }
            })
            .collect()
    };
    Some(SettingsState {
        window_mode: settings.window_mode as usize,
        window_modes: options(settings.window_modes, settings.window_mode_count),
        display: settings.display as usize,
        displays: options(settings.displays, settings.display_count),
        resolution: settings.resolution.max(0) as usize,
        resolutions: options(settings.resolutions, settings.resolution_count),
        resolution_current: unsafe {
            text_bytes(settings.resolution_current.text, settings.resolution_current.text_len)
        },
        resolution_missing: settings.resolution_missing != 0,
        sprint_mode: settings.sprint_mode as usize,
        sprint_modes: options(settings.sprint_modes, settings.sprint_mode_count),
        hud_opacity: settings.hud_opacity,
        reduce_motion: settings.reduce_motion != 0,
    })
}

/// # Safety
///
/// `panel` must point to a valid `UiPanel` whose pointers are readable for
/// their lengths or null, or be null.
pub unsafe fn panel_state(panel: *const UiPanel) -> Option<PanelState> {
    let panel = unsafe { panel.as_ref() }?;
    Some(PanelState {
        rows: unsafe { rows(panel.rows, panel.row_count) },
        notice: unsafe { text_bytes(panel.notice, panel.notice_len) },
        capture_hint: unsafe { text_bytes(panel.capture_hint, panel.capture_hint_len) },
        captured: panel.captured != 0,
        palette_open: panel.palette_open != 0,
    })
}

/// # Safety
///
/// `menu` must point to a valid `UiMenu` whose pointers are readable for their
/// lengths or null, or be null.
pub unsafe fn menu_state(menu: *const UiMenu) -> Option<MenuState> {
    let menu = unsafe { menu.as_ref() }?;
    Some(MenuState {
        open: menu.open != 0,
        title: unsafe { text_bytes(menu.title, menu.title_len) },
        note: unsafe { text_bytes(menu.note, menu.note_len) },
        hints: unsafe { hints(menu.hints, menu.hint_count) },
    })
}

/// # Safety
///
/// `palette` must point to a valid `UiPalette` whose pointers are readable for
/// their lengths or null, or be null.
pub unsafe fn palette_state(palette: *const UiPalette) -> Option<PaletteState> {
    let palette = unsafe { palette.as_ref() }?;
    let mut items = Vec::with_capacity(palette.item_count as usize);
    if !palette.items.is_null() {
        for index in 0..palette.item_count as usize {
            let item = unsafe { &*palette.items.add(index) };
            items.push(PaletteItem {
                name: unsafe { text_bytes(item.name, item.name_len) },
                short: unsafe { text_bytes(item.short, item.short_len) },
                half_extents: item.half_extents,
                color: item.color,
                base_pitch: item.base_pitch,
                body: unsafe { text_bytes(item.body, item.body_len) },
                key: unsafe { text_bytes(item.key, item.key_len) },
                light_line: unsafe { text_bytes(item.light_line, item.light_line_len) },
                emissive: item.emissive != 0,
            });
        }
    }
    Some(PaletteState {
        open: palette.open != 0,
        title: unsafe { text_bytes(palette.title, palette.title_len) },
        items,
        selected: palette.selected as usize,
        body: unsafe { text_bytes(palette.body, palette.body_len) },
        size: unsafe { text_bytes(palette.size, palette.size_len) },
        hints: unsafe { hints(palette.hints, palette.hint_count) },
    })
}
