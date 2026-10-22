use bevy::prelude::*;

use crate::arena::PlayerSpawn;

use super::{
    Player, PlayerCamera, PlayerConfig, PlayerGround, PlayerIntent, PlayerLook, PlayerVelocity,
    Stance,
};

pub fn reset_player(
    intent: Res<PlayerIntent>,
    spawn: Res<PlayerSpawn>,
    config: Res<PlayerConfig>,
    mut player: Query<
        (
            &mut Transform,
            &mut PlayerVelocity,
            &mut PlayerLook,
            &mut PlayerGround,
            &mut Stance,
        ),
        With<Player>,
    >,
    mut camera: Query<&mut Transform, (With<PlayerCamera>, Without<Player>)>,
) {
    let Ok((mut transform, mut velocity, mut look, mut ground, mut stance)) = player.single_mut()
    else {
        return;
    };

    let fell = transform.translation.y < -10.0;
    if !intent.reset && !fell {
        return;
    }

    let standing = Stance::Standing;
    transform.translation = Vec3::new(
        spawn.feet.x,
        spawn.feet.y + config.height(standing) * 0.5,
        spawn.feet.z,
    );
    transform.rotation = Quat::IDENTITY;

    *stance = standing;
    velocity.0 = Vec3::ZERO;
    *look = PlayerLook::default();
    *ground = PlayerGround::default();

    let Ok(mut camera) = camera.single_mut() else {
        return;
    };
    camera.translation = Vec3::new(0.0, config.eye_offset(standing), 0.0);
    camera.rotation = Quat::IDENTITY;
}
