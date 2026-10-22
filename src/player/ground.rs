use bevy::prelude::*;
use bevy_rapier3d::prelude::KinematicCharacterControllerOutput;

use super::{Player, PlayerConfig, PlayerGround, PlayerVelocity};

pub fn update_ground(
    time: Res<Time<Fixed>>,
    config: Res<PlayerConfig>,
    mut players: Query<
        (
            Option<&KinematicCharacterControllerOutput>,
            &PlayerVelocity,
            &mut PlayerGround,
        ),
        With<Player>,
    >,
) {
    let dt = time.delta_secs();
    let Ok((output, velocity, mut ground)) = players.single_mut() else {
        return;
    };

    let horizontal_speed = Vec3::new(velocity.0.x, 0.0, velocity.0.z).length();
    let grounded = output.is_some_and(|output| output.grounded) && velocity.0.y <= 0.0;

    if grounded && !ground.grounded {
        ground.air_cap = 0.0;
    } else if !grounded && ground.grounded {
        ground.air_cap = config.walk_speed.max(horizontal_speed);
    }

    ground.grounded = grounded;
    ground.coyote = if grounded {
        config.coyote_time
    } else {
        (ground.coyote - dt).max(0.0)
    };
    ground.jump_buffer = (ground.jump_buffer - dt).max(0.0);
}
