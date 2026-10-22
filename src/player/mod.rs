pub mod camera;
pub mod components;
pub mod config;
pub mod controller;
pub mod dive;
pub mod gait;
pub mod ground;
pub mod input;
pub mod jump;
pub mod look;
pub mod movement;
pub mod reset;
pub mod spawn;
pub mod stance;

pub use components::{
    Gait, Player, PlayerCamera, PlayerLook, PlayerMotion, PlayerVelocity, Stance,
};
pub use config::{InputMode, PlayerConfig};
pub use dive::DiveState;
pub use gait::PlayerGaitInput;
pub use input::{CursorCaptured, PlayerIntent};
pub use stance::PlayerStanceInput;

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
                    stance::apply_stance_input.after(input::sample_input),
                    gait::apply_gait_input.after(input::sample_input),
                    jump::buffer_jump.after(input::sample_input),
                    look::mouse_look.after(input::sample_input),
                    reset::reset_player
                        .after(input::sample_input)
                        .after(look::mouse_look),
                    toggle_debug.after(input::sample_input),
                    camera::update_projection,
                    camera::smooth_eye_height.after(reset::reset_player),
                ),
            )
            .add_systems(
                FixedUpdate,
                (
                    stance::apply_stance,
                    ground::update_ground,
                    dive::apply_dive,
                    jump::apply_jump,
                    movement::move_player,
                )
                    .chain()
                    .before(PhysicsSet::SyncBackend),
            );
    }
}

fn toggle_debug(intent: Res<PlayerIntent>, mut context: ResMut<DebugRenderContext>) {
    if intent.toggle_debug {
        context.enabled = !context.enabled;
    }
}
