pub mod arena;
pub mod hud;
pub mod player;

use bevy::prelude::*;
use bevy_rapier3d::prelude::*;

pub struct GamePlugin;

impl Plugin for GamePlugin {
    fn build(&self, app: &mut App) {
        app.insert_resource(Time::<Fixed>::from_hz(64.0))
            .insert_resource(TimestepMode::Fixed {
                dt: 1.0 / 64.0,
                substeps: 1,
            })
            .add_plugins((
                RapierPhysicsPlugin::<NoUserData>::default().in_fixed_schedule(),
                RapierDebugRenderPlugin::default().disabled(),
                arena::ArenaPlugin,
                player::PlayerPlugin,
                hud::HudPlugin,
            ));
    }
}
