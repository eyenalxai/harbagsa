use bevy::prelude::*;

use super::movement::yaw_direction;
use super::stance::PlayerStanceInput;
use super::{Player, PlayerConfig, PlayerIntent, PlayerLook, PlayerMotion, PlayerVelocity};

#[derive(Component, Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum DiveState {
    #[default]
    None,
    Diving,
    Sliding,
}

pub fn apply_dive(
    config: Res<PlayerConfig>,
    intent: Res<PlayerIntent>,
    mut players: Query<
        (
            &PlayerLook,
            &mut PlayerVelocity,
            &mut PlayerMotion,
            &mut PlayerStanceInput,
            &mut DiveState,
        ),
        With<Player>,
    >,
) {
    let Ok((look, mut velocity, mut ground, mut stance_input, mut dive)) = players.single_mut()
    else {
        return;
    };

    let requested = stance_input.dive_requested;
    stance_input.dive_requested = false;

    if requested && !ground.grounded && *dive == DiveState::None {
        let horizontal = velocity.horizontal();
        let direction = dive_direction(look.yaw, intent.move_axis, horizontal);
        velocity.0.x = direction.x * config.dive_speed;
        velocity.0.z = direction.z * config.dive_speed;
        *dive = DiveState::Diving;
        ground.jump_buffer = 0.0;
    }

    if *dive == DiveState::Diving && ground.grounded {
        let horizontal = velocity.horizontal();
        let direction = dive_direction(look.yaw, Vec2::ZERO, horizontal);
        let speed = slide_start_speed(config.prone_speed, config.dive_speed);
        velocity.0.x = direction.x * speed;
        velocity.0.z = direction.z * speed;
        *dive = DiveState::Sliding;
    }

    if *dive == DiveState::Sliding && !ground.grounded {
        *dive = DiveState::Diving;
    }
}

pub fn dive_direction(yaw: f32, axis: Vec2, horizontal: Vec3) -> Vec3 {
    if axis.length_squared() > 0.0 {
        yaw_direction(yaw, axis)
    } else if horizontal.length_squared() > 0.01 {
        horizontal.normalize()
    } else {
        yaw_direction(yaw, Vec2::Y)
    }
}

pub const SLIDE_SPEED_FACTOR: f32 = 0.55;

pub fn slide_start_speed(prone_speed: f32, dive_speed: f32) -> f32 {
    (dive_speed * SLIDE_SPEED_FACTOR).max(prone_speed)
}

pub fn slide_step(current_speed: f32, prone_speed: f32, decel: f32, dt: f32) -> f32 {
    (current_speed - decel * dt).max(prone_speed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn input_direction_wins() {
        let direction = dive_direction(0.0, Vec2::new(1.0, 0.0), Vec3::NEG_Z);
        assert!((direction - Vec3::X).length() < 0.0001);
    }

    #[test]
    fn horizontal_velocity_is_the_fallback() {
        let direction = dive_direction(0.0, Vec2::ZERO, Vec3::NEG_Z * 4.0);
        assert!((direction - Vec3::NEG_Z).length() < 0.0001);
    }

    #[test]
    fn camera_forward_is_the_last_fallback() {
        let direction = dive_direction(0.0, Vec2::ZERO, Vec3::ZERO);
        assert!((direction - Vec3::NEG_Z).length() < 0.0001);
    }

    #[test]
    fn dive_direction_is_normalized() {
        let direction = dive_direction(0.7, Vec2::new(1.0, 1.0), Vec3::ZERO);
        assert!((direction.length() - 1.0).abs() < 0.0001);
    }

    #[test]
    fn slide_starts_at_the_dive_speed_fraction() {
        let speed = slide_start_speed(1.2, 11.0);
        assert!((speed - 6.05).abs() < 0.0001);
    }

    #[test]
    fn slide_never_drops_below_prone_speed() {
        let speed = slide_step(1.2, 1.2, 18.0, 1.0 / 64.0);
        assert!((speed - 1.2).abs() < 0.0001);
    }

    #[test]
    fn slide_reaches_prone_speed_in_under_half_a_second() {
        let dt = 1.0 / 64.0;
        let mut speed = slide_start_speed(1.2, 11.0);
        let mut steps = 0;
        while speed > 1.2 + 0.01 && steps < 100 {
            speed = slide_step(speed, 1.2, 18.0, dt);
            steps += 1;
        }
        assert!(steps < 32);
    }
}
