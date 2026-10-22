pub mod camera;
pub mod components;
pub mod config;
pub mod controller;
pub mod input;
pub mod look;
pub mod movement;
pub mod reset;
pub mod spawn;

pub use components::{
    Gait, Player, PlayerCamera, PlayerGround, PlayerLook, PlayerVelocity, Stance,
};
pub use config::{InputMode, PlayerConfig};
pub use input::{CursorCaptured, PlayerIntent};

use bevy::input::InputSystems;
use bevy::prelude::*;
use bevy_rapier3d::prelude::*;

pub struct PlayerPlugin;

impl Plugin for PlayerPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<PlayerConfig>()
            .init_resource::<PlayerIntent>()
            .init_resource::<CursorCaptured>()
            .add_systems(Startup, spawn::spawn_player)
            .add_systems(
                Update,
                (
                    input::sample_input.after(InputSystems),
                    look::mouse_look.after(input::sample_input),
                    reset::reset_player.after(input::sample_input),
                    toggle_debug.after(input::sample_input),
                    camera::update_projection,
                ),
            )
            .add_systems(
                FixedUpdate,
                movement::move_player.before(PhysicsSet::SyncBackend),
            );
    }
}

fn toggle_debug(intent: Res<PlayerIntent>, mut context: ResMut<DebugRenderContext>) {
    if intent.toggle_debug {
        context.enabled = !context.enabled;
    }
}
