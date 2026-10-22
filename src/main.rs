use bevy::prelude::*;
use bevy::window::WindowResolution;
use harbagsa::GamePlugin;

fn main() {
    App::new()
        .add_plugins(DefaultPlugins.set(WindowPlugin {
            primary_window: Some(Window {
                title: "harbagsa".into(),
                resolution: WindowResolution::new(1280, 720),
                ..default()
            }),
            ..default()
        }))
        .insert_resource(ClearColor(Color::srgb(0.45, 0.60, 0.80)))
        .add_plugins(GamePlugin)
        .run();
}
