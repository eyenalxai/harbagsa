use rune::{Key, KeyEvent, Mods, Runtime};

use crate::abi::UiEvent;
use crate::introspect;
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

const FRAME_DT: f64 = 1.0 / 60.0;
const MAX_DRAG_STEPS: u32 = 64;

pub fn dispatch(runtime: &mut Runtime<UiState>, events: *const UiEvent, count: u32) {
    if events.is_null() {
        return;
    }
    for index in 0..count as usize {
        let event = unsafe { &*events.add(index) };
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
                runtime.wheel(event.x, event.y, -event.dy * 40.0);
            }
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

pub fn click_point(runtime: &mut Runtime<UiState>, x: f32, y: f32, key: Option<&str>) {
    runtime.pointer_move(x, y);
    runtime.pointer_down(x, y);
    runtime.state.pressed_key =
        key.map(str::to_string).or_else(|| introspect::key_at(runtime, x, y));
    advance(runtime);
    runtime.pointer_up(x, y);
    runtime.state.pressed_key = None;
    advance(runtime);
    settle(runtime);
}

pub fn drag_point(
    runtime: &mut Runtime<UiState>,
    x: f32,
    y: f32,
    dx: f32,
    dy: f32,
    steps: u32,
    hold: bool,
    cancel: bool,
    key: Option<&str>,
) {
    let steps = steps.clamp(1, MAX_DRAG_STEPS);
    runtime.pointer_move(x, y);
    runtime.pointer_down(x, y);
    runtime.state.pressed_key =
        key.map(str::to_string).or_else(|| introspect::key_at(runtime, x, y));
    advance(runtime);
    for step in 1..=steps {
        let fraction = step as f32 / steps as f32;
        runtime.pointer_move(x + dx * fraction, y + dy * fraction);
        advance(runtime);
    }
    if hold {
        settle(runtime);
        return;
    }
    if cancel {
        runtime.window_focus(false);
        runtime.state.pressed_key = None;
        advance(runtime);
        runtime.window_focus(true);
        advance(runtime);
    } else {
        runtime.pointer_up(x + dx, y + dy);
        runtime.state.pressed_key = None;
        advance(runtime);
    }
    settle(runtime);
}

pub fn drag_element(
    runtime: &mut Runtime<UiState>,
    key: &str,
    dx: f32,
    dy: f32,
    steps: u32,
    hold: bool,
    cancel: bool,
) -> i32 {
    let Some((x, y)) = introspect::element_center(runtime, key) else {
        return 3;
    };
    drag_point(runtime, x, y, dx, dy, steps, hold, cancel, Some(key));
    0
}

pub fn wheel_point(runtime: &mut Runtime<UiState>, x: f32, y: f32, dx: f32, dy: f32) {
    runtime.pointer_move(x, y);
    runtime.wheel_xy(x, y, dx, dy);
    advance(runtime);
    settle(runtime);
}

pub fn wheel_element(
    runtime: &mut Runtime<UiState>,
    key: &str,
    dx: f32,
    dy: f32,
) -> i32 {
    let Some((x, y)) = introspect::element_center(runtime, key) else {
        return 3;
    };
    wheel_point(runtime, x, y, dx, dy);
    0
}

pub fn focus(runtime: &mut Runtime<UiState>, focused: bool) {
    runtime.window_focus(focused);
    if !focused {
        runtime.state.pressed_key = None;
    }
    advance(runtime);
    settle(runtime);
}

fn advance(runtime: &mut Runtime<UiState>) {
    runtime.invalidate();
    runtime.frame(FRAME_DT);
}

fn settle(runtime: &mut Runtime<UiState>) {
    runtime.settle_all();
    runtime.frame(FRAME_DT);
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
