use bevy::prelude::*;

use crate::player::{CursorCaptured, input::sample_input};

pub struct HudPlugin;

impl Plugin for HudPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, spawn_capture_overlay)
            .add_systems(Update, update_capture_overlay.after(sample_input));
    }
}

#[derive(Component)]
struct CaptureOverlay;

fn spawn_capture_overlay(mut commands: Commands) {
    commands.spawn((
        CaptureOverlay,
        Node {
            position_type: PositionType::Absolute,
            width: percent(100),
            height: percent(100),
            align_items: AlignItems::Center,
            justify_content: JustifyContent::Center,
            ..default()
        },
        BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.35)),
        children![(
            Text::new("Click to capture mouse"),
            TextFont::from_font_size(28.0),
            TextColor(Color::WHITE),
        )],
    ));
}

fn update_capture_overlay(
    captured: Res<CursorCaptured>,
    mut overlay: Query<&mut Visibility, With<CaptureOverlay>>,
) {
    let Ok(mut visibility) = overlay.single_mut() else {
        return;
    };
    *visibility = if captured.0 {
        Visibility::Hidden
    } else {
        Visibility::Inherited
    };
}
