use bevy::prelude::*;
use bevy_rapier3d::prelude::*;

use super::dive::DiveState;
use super::{
    Gait, Player, PlayerConfig, PlayerGround, PlayerIntent, PlayerLook, PlayerVelocity, Stance,
};

type MovementQuery<'w, 's> = Query<
    'w,
    's,
    (
        &'static mut KinematicCharacterController,
        &'static PlayerLook,
        &'static mut PlayerVelocity,
        &'static PlayerGround,
        &'static Stance,
        &'static Gait,
        &'static mut DiveState,
    ),
    With<Player>,
>;

pub fn move_player(
    time: Res<Time<Fixed>>,
    config: Res<PlayerConfig>,
    intent: Res<PlayerIntent>,
    mut player: MovementQuery,
) {
    let dt = time.delta_secs();
    if dt <= 0.0 {
        return;
    }

    let Ok((mut controller, look, mut velocity, ground, stance, gait, mut dive)) =
        player.single_mut()
    else {
        return;
    };

    let direction = yaw_direction(look.yaw, intent.move_axis);
    let horizontal = Vec3::new(velocity.0.x, 0.0, velocity.0.z);

    let horizontal = match *dive {
        DiveState::Sliding => {
            let heading = horizontal.normalize_or_zero();
            let target = heading * config.prone_speed;
            let next = move_towards(horizontal, target, config.slide_decel * dt);
            if next.length() <= config.prone_speed + 0.02 {
                *dive = DiveState::None;
            }
            next
        }
        DiveState::Diving => horizontal,
        DiveState::None if ground.grounded => {
            let target = direction * config.speed(*stance, *gait);
            let acceleration = if direction.length_squared() > 0.0 {
                config.ground_accel
            } else {
                config.ground_decel
            };
            move_towards(horizontal, target, acceleration * dt)
        }
        DiveState::None => {
            if direction.length_squared() > 0.0 {
                let cap = ground.air_cap.max(config.walk_speed);
                move_towards(horizontal, direction * cap, config.air_accel * dt)
            } else {
                horizontal
            }
        }
    };

    let mut vertical = velocity.0.y;
    if ground.grounded && vertical < 0.0 {
        vertical = 0.0;
    }
    vertical -= config.gravity * dt;

    velocity.0 = Vec3::new(horizontal.x, vertical, horizontal.z);
    controller.translation = Some(velocity.0 * dt);
}

pub fn yaw_direction(yaw: f32, axis: Vec2) -> Vec3 {
    let forward = Vec3::new(-yaw.sin(), 0.0, -yaw.cos());
    let right = Vec3::new(yaw.cos(), 0.0, -yaw.sin());
    (forward * axis.y + right * axis.x).normalize_or_zero()
}

pub fn move_towards(current: Vec3, target: Vec3, max_delta: f32) -> Vec3 {
    let delta = target - current;
    let distance = delta.length();
    if distance <= max_delta || distance == 0.0 {
        target
    } else {
        current + delta / distance * max_delta
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::f32::consts::FRAC_PI_2;

    #[test]
    fn forward_at_zero_yaw_is_negative_z() {
        let direction = yaw_direction(0.0, Vec2::new(0.0, 1.0));
        assert!((direction - Vec3::NEG_Z).length() < 0.0001);
    }

    #[test]
    fn right_at_zero_yaw_is_positive_x() {
        let direction = yaw_direction(0.0, Vec2::new(1.0, 0.0));
        assert!((direction - Vec3::X).length() < 0.0001);
    }

    #[test]
    fn forward_at_ninety_degrees_yaw_is_negative_x() {
        let direction = yaw_direction(FRAC_PI_2, Vec2::new(0.0, 1.0));
        assert!((direction - Vec3::NEG_X).length() < 0.0001);
    }

    #[test]
    fn backward_and_strafe_directions_are_opposites() {
        let forward = yaw_direction(0.0, Vec2::new(0.0, 1.0));
        let backward = yaw_direction(0.0, Vec2::new(0.0, -1.0));
        let left = yaw_direction(0.0, Vec2::new(-1.0, 0.0));
        let right = yaw_direction(0.0, Vec2::new(1.0, 0.0));
        assert!((forward + backward).length() < 0.0001);
        assert!((left + right).length() < 0.0001);
    }

    #[test]
    fn diagonal_direction_is_normalized() {
        let direction = yaw_direction(0.0, Vec2::new(1.0, 1.0).normalize());
        assert!((direction.length() - 1.0).abs() < 0.0001);
    }

    #[test]
    fn move_towards_reaches_the_target_in_one_step() {
        let current = Vec3::ZERO;
        let target = Vec3::X * 4.0;
        let result = move_towards(current, target, 10.0);
        assert!((result - target).length() < 0.0001);
    }

    #[test]
    fn move_towards_limits_the_step() {
        let current = Vec3::ZERO;
        let target = Vec3::X * 4.0;
        let result = move_towards(current, target, 1.0);
        assert!((result.length() - 1.0).abs() < 0.0001);
        assert!((result - Vec3::X).length() < 0.0001);
    }
}
