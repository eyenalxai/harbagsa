use bevy::prelude::*;
use bevy_rapier3d::prelude::KinematicCharacterControllerOutput;

use super::{Player, PlayerConfig, PlayerMotion, PlayerVelocity};

pub fn update_ground(
    time: Res<Time<Fixed>>,
    config: Res<PlayerConfig>,
    mut players: Query<
        (
            Option<&KinematicCharacterControllerOutput>,
            &PlayerVelocity,
            &mut PlayerMotion,
        ),
        With<Player>,
    >,
) {
    let dt = time.delta_secs();
    let Ok((output, velocity, mut ground)) = players.single_mut() else {
        return;
    };

    let horizontal_speed = velocity.horizontal().length();
    let grounded = output.is_some_and(|output| output.grounded) && velocity.0.y <= 0.0;

    if grounded && !ground.grounded {
        ground.air_cap = 0.0;
    } else if !grounded && ground.grounded {
        ground.air_cap = air_cap(config.walk_speed, horizontal_speed);
    }

    ground.grounded = grounded;
    ground.coyote = if grounded {
        config.coyote_time
    } else {
        (ground.coyote - dt).max(0.0)
    };
    ground.jump_buffer = (ground.jump_buffer - dt).max(0.0);
}

pub fn air_cap(walk_speed: f32, takeoff_speed: f32) -> f32 {
    walk_speed.max(takeoff_speed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn air_cap_never_drops_below_walk_speed() {
        assert!((air_cap(5.0, 2.4) - 5.0).abs() < f32::EPSILON);
    }

    #[test]
    fn air_cap_keeps_sprint_speed() {
        assert!((air_cap(5.0, 8.0) - 8.0).abs() < f32::EPSILON);
    }
}
