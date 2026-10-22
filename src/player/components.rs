use bevy::prelude::*;

#[derive(Component)]
pub struct Player;

#[derive(Component)]
pub struct PlayerCamera;

#[derive(Component, Debug, Default)]
pub struct PlayerVelocity(pub Vec3);

#[derive(Component, Debug, Default)]
pub struct PlayerGround {
    pub grounded: bool,
    pub coyote: f32,
}

#[derive(Component, Debug, Default, Clone, Copy)]
pub struct PlayerLook {
    pub yaw: f32,
    pub pitch: f32,
}

#[derive(Component, Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum Stance {
    #[default]
    Standing,
    Crouching,
    Prone,
}

#[derive(Component, Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum Gait {
    #[default]
    Walk,
    Sprint,
}
