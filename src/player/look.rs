use bevy::prelude::*;

use super::{Player, PlayerCamera, PlayerConfig, PlayerIntent, PlayerLook};

const PITCH_LIMIT: f32 = 89.0 * std::f32::consts::PI / 180.0;

pub fn mouse_look(
    intent: Res<PlayerIntent>,
    config: Res<PlayerConfig>,
    mut player: Query<(&mut Transform, &mut PlayerLook), With<Player>>,
    mut camera: Query<&mut Transform, (With<PlayerCamera>, Without<Player>)>,
) {
    let Ok((mut body, mut look)) = player.single_mut() else {
        return;
    };

    look.yaw -= intent.look_delta.x * config.mouse_yaw_sensitivity;
    look.pitch = (look.pitch - intent.look_delta.y * config.mouse_pitch_sensitivity)
        .clamp(-PITCH_LIMIT, PITCH_LIMIT);

    body.rotation = Quat::from_rotation_y(look.yaw);

    let Ok(mut camera) = camera.single_mut() else {
        return;
    };
    camera.rotation = Quat::from_rotation_x(look.pitch);
}
