use bevy::input::mouse::AccumulatedMouseMotion;
use bevy::prelude::*;
use bevy::window::{CursorGrabMode, CursorOptions, PrimaryWindow};

#[derive(Resource, Debug, Default)]
pub struct PlayerIntent {
    pub move_axis: Vec2,
    pub look_delta: Vec2,
    pub reset: bool,
    pub toggle_debug: bool,
    pub crouch_held: bool,
    pub crouch_pressed: bool,
    pub prone_held: bool,
    pub prone_pressed: bool,
    pub sprint_held: bool,
    pub sprint_pressed: bool,
    pub jump_pressed: bool,
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
    intent.crouch_held = false;
    intent.crouch_pressed = false;
    intent.prone_held = false;
    intent.prone_pressed = false;
    intent.sprint_held = false;
    intent.sprint_pressed = false;
    intent.jump_pressed = false;

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
    intent.crouch_held = keyboard.pressed(KeyCode::KeyC);
    intent.crouch_pressed = keyboard.just_pressed(KeyCode::KeyC);
    intent.prone_held = keyboard.pressed(KeyCode::KeyZ);
    intent.prone_pressed = keyboard.just_pressed(KeyCode::KeyZ);
    intent.sprint_held =
        keyboard.pressed(KeyCode::ShiftLeft) || keyboard.pressed(KeyCode::ShiftRight);
    intent.sprint_pressed =
        keyboard.just_pressed(KeyCode::ShiftLeft) || keyboard.just_pressed(KeyCode::ShiftRight);
    intent.jump_pressed = keyboard.just_pressed(KeyCode::Space);
}

fn release_cursor(cursor: &mut CursorOptions) {
    cursor.visible = true;
    cursor.grab_mode = CursorGrabMode::None;
}
