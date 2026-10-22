use bevy::prelude::*;

use crate::player::{
    CursorCaptured, DiveState, Gait, Player, PlayerMotion, PlayerVelocity, Stance,
};

pub struct HudPlugin;

impl Plugin for HudPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, spawn_hud)
            .add_systems(Update, (update_readout, update_capture_overlay));
    }
}

#[derive(Component)]
struct HudReadout;

#[derive(Component)]
struct CaptureOverlay;

fn spawn_hud(mut commands: Commands) {
    spawn_crosshair(&mut commands);
    spawn_readout(&mut commands);
    spawn_controls(&mut commands);
    spawn_capture_overlay(&mut commands);
}

fn spawn_crosshair(commands: &mut Commands) {
    commands
        .spawn(Node {
            position_type: PositionType::Absolute,
            left: percent(50),
            top: percent(50),
            width: px(0),
            height: px(0),
            ..default()
        })
        .with_children(|parent| {
            parent.spawn((
                Node {
                    position_type: PositionType::Absolute,
                    left: px(-1),
                    top: px(-8),
                    width: px(2),
                    height: px(16),
                    border_radius: BorderRadius::all(px(1)),
                    ..default()
                },
                BackgroundColor(Color::WHITE),
            ));
            parent.spawn((
                Node {
                    position_type: PositionType::Absolute,
                    left: px(-8),
                    top: px(-1),
                    width: px(16),
                    height: px(2),
                    border_radius: BorderRadius::all(px(1)),
                    ..default()
                },
                BackgroundColor(Color::WHITE),
            ));
        });
}

fn spawn_readout(commands: &mut Commands) {
    commands.spawn((
        Node {
            position_type: PositionType::Absolute,
            top: px(12),
            left: px(12),
            padding: UiRect::all(px(10)),
            border_radius: BorderRadius::all(px(6)),
            ..default()
        },
        BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.55)),
        children![(
            HudReadout,
            Text::new("Stance: Standing"),
            TextFont::from_font_size(16.0),
            TextColor(Color::WHITE),
        )],
    ));
}

fn spawn_controls(commands: &mut Commands) {
    commands.spawn((
        Node {
            position_type: PositionType::Absolute,
            bottom: px(12),
            left: px(12),
            padding: UiRect::all(px(8)),
            border_radius: BorderRadius::all(px(6)),
            ..default()
        },
        BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.45)),
        children![(
            Text::new(
                "WASD move   Mouse look\nShift sprint   Space jump\nC crouch   Z prone   R reset   F1 debug"
            ),
            TextFont::from_font_size(14.0),
            TextColor(Color::srgba(1.0, 1.0, 1.0, 0.85)),
        )],
    ));
}

fn spawn_capture_overlay(commands: &mut Commands) {
    commands.spawn((
        CaptureOverlay,
        Node {
            position_type: PositionType::Absolute,
            left: px(0),
            top: px(0),
            right: px(0),
            bottom: px(0),
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

fn update_readout(
    player: Query<(&Stance, &Gait, &PlayerMotion, &PlayerVelocity, &DiveState), With<Player>>,
    mut readout: Query<&mut Text, With<HudReadout>>,
) {
    let Ok((stance, gait, ground, velocity, dive)) = player.single() else {
        return;
    };
    let Ok(mut readout) = readout.single_mut() else {
        return;
    };

    let speed = velocity.horizontal().length();
    **readout = format!(
        "Stance: {}\nGait: {}\nSpeed: {:.1} m/s\nGrounded: {}\nDive: {}",
        stance_label(*stance),
        gait_label(*gait),
        speed,
        if ground.grounded { "yes" } else { "no" },
        dive_label(*dive),
    );
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

fn stance_label(stance: Stance) -> &'static str {
    match stance {
        Stance::Standing => "Standing",
        Stance::Crouching => "Crouching",
        Stance::Prone => "Prone",
    }
}

fn gait_label(gait: Gait) -> &'static str {
    match gait {
        Gait::Walk => "Walk",
        Gait::Sprint => "Sprint",
    }
}

fn dive_label(dive: DiveState) -> &'static str {
    if dive == DiveState::None { "no" } else { "yes" }
}
