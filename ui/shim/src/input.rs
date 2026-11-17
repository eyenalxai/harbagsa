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

pub const MOD_SHIFT: u32 = 1;
pub const MOD_CTRL: u32 = 2;

const LIVE_WHEEL_POINTS: f32 = 40.0;

pub fn dispatch(runtime: &mut Runtime<UiState>, events: *const UiEvent, count: u32) {
    if events.is_null() {
        return;
    }
    for index in 0..count as usize {
        let event = unsafe { &*events.add(index) };
        let mods = Mods {
            shift: event.mods & MOD_SHIFT != 0,
            ctrl: event.mods & MOD_CTRL != 0,
            cmd: event.mods & MOD_CTRL != 0,
            ..Mods::default()
        };
        match event.kind {
            POINTER_MOVE => runtime.pointer_move(event.x, event.y),
            POINTER_DOWN => runtime.pointer_down(event.x, event.y),
            POINTER_UP => {
                runtime.pointer_up(event.x, event.y);
                runtime.state.pressed_key = None;
            }
            POINTER_LEAVE => {
                runtime.pointer_leave();
                runtime.state.pressed_key = None;
            }
            WHEEL => {
                runtime.pointer_move(event.x, event.y);
                runtime.wheel(event.x, event.y, -event.dy * LIVE_WHEEL_POINTS);
            }
            KEY_DOWN => {
                if let Some(key) = key_from_code(event.key) {
                    runtime.key(KeyEvent { key, mods });
                }
            }
            KEY_UP => {
                if let Some(key) = key_from_code(event.key) {
                    runtime.key_up(KeyEvent { key, mods });
                }
            }
            KEY_REPEAT => {
                if let Some(key) = key_from_code(event.key) {
                    runtime.repeat_key(KeyEvent { key, mods });
                }
            }
            FOCUS => {
                runtime.window_focus(event.flags & 1 != 0);
                if event.flags & 1 == 0 {
                    runtime.state.pressed_key = None;
                }
            }
            _ => {}
        }
    }
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
        8 => Key::Text(" ".into()),
        _ => return None,
    })
}
