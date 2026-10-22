use bevy::prelude::*;

#[derive(Component)]
pub struct Player;

#[derive(Component)]
pub struct PlayerCamera;

#[derive(Component, Debug, Default)]
pub struct PlayerVelocity(pub Vec3);

impl PlayerVelocity {
    pub fn horizontal(&self) -> Vec3 {
        Vec3::new(self.0.x, 0.0, self.0.z)
    }
}

#[derive(Component, Debug, Default)]
pub struct PlayerMotion {
    pub grounded: bool,
    pub coyote: f32,
    pub jump_buffer: f32,
    pub air_cap: f32,
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
