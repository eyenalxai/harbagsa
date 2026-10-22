use bevy::input::mouse::AccumulatedMouseMotion;
use bevy::prelude::*;
use bevy::window::{CursorGrabMode, CursorOptions, PrimaryWindow};

#[derive(Resource, Debug, Default)]
pub struct PlayerIntent {
    pub move_axis: Vec2,
    pub look_delta: Vec2,
    pub reset: bool,
    pub toggle_debug: bool,
}

#[derive(Resource, Debug, Default)]
pub struct CursorCaptured(pub bool);

pub fn sample_input(
    keyboard: Res<ButtonInput<KeyCode>>,
    mouse: Res<ButtonInput<MouseButton>>,
    motion: Res<AccumulatedMouseMotion>,
    mut intent: ResMut<PlayerIntent>,
    mut captured: ResMut<CursorCaptured>,
    mut windows: Query<(&Window, &mut CursorOptions), With<PrimaryWindow>>,
) {
    let Ok((window, mut cursor)) = windows.single_mut() else {
        return;
    };

    if !window.focused || keyboard.just_pressed(KeyCode::Escape) {
        release_cursor(&mut cursor);
    }

    let is_captured = cursor.grab_mode != CursorGrabMode::None;
    if window.focused && mouse.just_pressed(MouseButton::Left) && !is_captured {
        cursor.visible = false;
        cursor.grab_mode = CursorGrabMode::Locked;
    }

    let is_captured = cursor.grab_mode != CursorGrabMode::None;
    captured.0 = is_captured;

    intent.reset = keyboard.just_pressed(KeyCode::KeyR);
    intent.toggle_debug = keyboard.just_pressed(KeyCode::F1);
    intent.move_axis = Vec2::ZERO;
    intent.look_delta = Vec2::ZERO;

    if !is_captured || !window.focused {
        return;
    }

    let mut axis = Vec2::ZERO;
    if keyboard.pressed(KeyCode::KeyW) {
        axis.y += 1.0;
    }
    if keyboard.pressed(KeyCode::KeyS) {
        axis.y -= 1.0;
    }
    if keyboard.pressed(KeyCode::KeyD) {
        axis.x += 1.0;
    }
    if keyboard.pressed(KeyCode::KeyA) {
        axis.x -= 1.0;
    }

    intent.move_axis = axis.normalize_or_zero();
    intent.look_delta = motion.delta;
}

fn release_cursor(cursor: &mut CursorOptions) {
    cursor.visible = true;
    cursor.grab_mode = CursorGrabMode::None;
}
