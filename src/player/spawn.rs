use bevy::prelude::*;
use bevy_rapier3d::prelude::Collider;

use crate::arena::PlayerSpawn;

use super::dive::DiveState;
use super::gait::PlayerGaitInput;
use super::stance::PlayerStanceInput;
use super::{
    Gait, Player, PlayerCamera, PlayerConfig, PlayerGround, PlayerLook, PlayerVelocity, Stance,
    controller::character_controller,
};

pub fn spawn_player(mut commands: Commands, config: Res<PlayerConfig>, spawn: Res<PlayerSpawn>) {
    let stance = Stance::Standing;
    let feet = spawn.feet;

    commands
        .spawn((
            Player,
            stance,
            Gait::Walk,
            PlayerVelocity::default(),
            PlayerLook::default(),
            PlayerGround::default(),
            PlayerStanceInput::default(),
            PlayerGaitInput::default(),
            DiveState::default(),
            Transform::from_xyz(feet.x, feet.y + config.height(stance) * 0.5, feet.z),
            Visibility::default(),
            Collider::capsule_y(config.half_height(stance), config.capsule_radius),
            character_controller(&config),
        ))
        .with_children(|parent| {
            parent.spawn((
                PlayerCamera,
                Camera3d::default(),
                Projection::from(PerspectiveProjection {
                    fov: 60.0_f32.to_radians(),
                    near: config.near_plane,
                    ..default()
                }),
                Transform::from_xyz(0.0, config.eye_offset(stance), 0.0),
            ));
        });
}
