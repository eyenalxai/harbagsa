use rune::{Key, KeyEvent, Mods, Runtime};

use crate::abi::UiEvent;
use crate::state::UiState;

pub const POINTER_MOVE: u32 = 1;
pub const POINTER_DOWN: u32 = 2;
pub const POINTER_UP: u32 = 3;
pub const POINTER_LEAVE: u32 = 4;
pub const WHEEL: u32 = 7;
pub const KEY_DOWN: u32 = 8;
pub const KEY_UP: u32 = 9;
pub const KEY_REPEAT: u32 = 10;
pub const FOCUS: u32 = 11;

pub fn dispatch(runtime: &mut Runtime<UiState>, events: *const UiEvent, count: u32) {
    if events.is_null() {
        return;
    }
    for index in 0..count as usize {
        let event = unsafe { &*events.add(index) };
        match event.kind {
            POINTER_MOVE => runtime.pointer_move(event.x, event.y),
            POINTER_DOWN => runtime.pointer_down(event.x, event.y),
            POINTER_UP => runtime.pointer_up(event.x, event.y),
            POINTER_LEAVE => runtime.pointer_leave(),
            WHEEL => runtime.wheel(event.x, event.y, -event.dy * 40.0),
            KEY_DOWN => {
                if let Some(key) = key_from_code(event.key) {
                    runtime.key(KeyEvent { key, mods: Mods::default() });
                }
            }
            KEY_UP => {
                if let Some(key) = key_from_code(event.key) {
                    runtime.key_up(KeyEvent { key, mods: Mods::default() });
                }
            }
            KEY_REPEAT => {
                if let Some(key) = key_from_code(event.key) {
                    runtime.repeat_key(KeyEvent { key, mods: Mods::default() });
                }
            }
            FOCUS => runtime.window_focus(event.flags & 1 != 0),
            _ => {}
        }
    }
}

pub fn click_point(runtime: &mut Runtime<UiState>, x: f32, y: f32) -> i32 {
    runtime.pointer_move(x, y);
    runtime.pointer_down(x, y);
    runtime.pointer_up(x, y);
    runtime.invalidate();
    runtime.frame(0.0);
    runtime.settle_all();
    0
}

pub fn click_element(runtime: &mut Runtime<UiState>, key: &str) -> i32 {
    let Some((x, y)) = runtime.find(key) else {
        return 3;
    };
    click_point(runtime, x, y)
}

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
