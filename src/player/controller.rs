use bevy::prelude::*;
use bevy_rapier3d::control::{CharacterAutostep, CharacterLength, KinematicCharacterController};

use super::PlayerConfig;

pub fn character_controller(config: &PlayerConfig) -> KinematicCharacterController {
    KinematicCharacterController {
        up: Vec3::Y,
        offset: CharacterLength::Absolute(config.controller_offset),
        slide: true,
        autostep: Some(CharacterAutostep {
            max_height: CharacterLength::Absolute(config.autostep_height),
            min_width: CharacterLength::Absolute(config.autostep_width),
            include_dynamic_bodies: false,
        }),
        max_slope_climb_angle: config.max_climb_angle.to_radians(),
        min_slope_slide_angle: config.min_slide_angle.to_radians(),
        apply_impulse_to_dynamic_bodies: true,
        custom_mass: Some(config.character_mass),
        snap_to_ground: Some(CharacterLength::Absolute(config.ground_snap)),
        ..default()
    }
}
