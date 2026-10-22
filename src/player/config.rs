use bevy::prelude::*;

use super::components::{Gait, Stance};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum InputMode {
    #[default]
    Hold,
    Toggle,
}

#[derive(Resource, Clone, Debug)]
pub struct PlayerConfig {
    pub capsule_radius: f32,
    pub stand_height: f32,
    pub crouch_height: f32,
    pub prone_height: f32,
    pub stand_eye: f32,
    pub crouch_eye: f32,
    pub prone_eye: f32,
    pub walk_speed: f32,
    pub sprint_speed: f32,
    pub crouch_speed: f32,
    pub prone_speed: f32,
    pub dive_speed: f32,
    pub ground_accel: f32,
    pub ground_decel: f32,
    pub air_accel: f32,
    pub gravity: f32,
    pub jump_speed: f32,
    pub coyote_time: f32,
    pub jump_buffer: f32,
    pub eye_smoothing: f32,
    pub mouse_yaw_sensitivity: f32,
    pub mouse_pitch_sensitivity: f32,
    pub horizontal_fov_degrees: f32,
    pub near_plane: f32,
    pub controller_offset: f32,
    pub autostep_height: f32,
    pub autostep_width: f32,
    pub max_climb_angle: f32,
    pub min_slide_angle: f32,
    pub ground_snap: f32,
    pub character_mass: f32,
    pub slide_decel: f32,
    pub sprint_mode: InputMode,
    pub crouch_mode: InputMode,
    pub prone_mode: InputMode,
}

impl Default for PlayerConfig {
    fn default() -> Self {
        Self {
            capsule_radius: 0.35,
            stand_height: 1.80,
            crouch_height: 1.20,
            prone_height: 0.70,
            stand_eye: 1.65,
            crouch_eye: 1.05,
            prone_eye: 0.30,
            walk_speed: 5.0,
            sprint_speed: 8.0,
            crouch_speed: 2.4,
            prone_speed: 1.2,
            dive_speed: 11.0,
            ground_accel: 60.0,
            ground_decel: 80.0,
            air_accel: 15.0,
            gravity: 18.0,
            jump_speed: 6.0,
            coyote_time: 0.10,
            jump_buffer: 0.12,
            eye_smoothing: 25.0,
            mouse_yaw_sensitivity: 0.0022,
            mouse_pitch_sensitivity: 0.0018,
            horizontal_fov_degrees: 90.0,
            near_plane: 0.05,
            controller_offset: 0.01,
            autostep_height: 0.35,
            autostep_width: 0.20,
            max_climb_angle: 45.0,
            min_slide_angle: 30.0,
            ground_snap: 0.30,
            character_mass: 75.0,
            slide_decel: 18.0,
            sprint_mode: InputMode::Hold,
            crouch_mode: InputMode::Toggle,
            prone_mode: InputMode::Toggle,
        }
    }
}

impl PlayerConfig {
    pub fn height(&self, stance: Stance) -> f32 {
        match stance {
            Stance::Standing => self.stand_height,
            Stance::Crouching => self.crouch_height,
            Stance::Prone => self.prone_height,
        }
    }

    pub fn half_height(&self, stance: Stance) -> f32 {
        (self.height(stance) * 0.5 - self.capsule_radius).max(0.0)
    }

    pub fn eye_height(&self, stance: Stance) -> f32 {
        match stance {
            Stance::Standing => self.stand_eye,
            Stance::Crouching => self.crouch_eye,
            Stance::Prone => self.prone_eye,
        }
    }

    pub fn eye_offset(&self, stance: Stance) -> f32 {
        self.eye_height(stance) - self.height(stance) * 0.5
    }

    pub fn speed(&self, stance: Stance, gait: Gait) -> f32 {
        match stance {
            Stance::Standing => match gait {
                Gait::Walk => self.walk_speed,
                Gait::Sprint => self.sprint_speed,
            },
            Stance::Crouching => self.crouch_speed,
            Stance::Prone => self.prone_speed,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config() -> PlayerConfig {
        PlayerConfig::default()
    }

    #[test]
    fn capsule_heights_match_the_spec() {
        let config = config();
        assert!((config.height(Stance::Standing) - 1.80).abs() < f32::EPSILON);
        assert!((config.height(Stance::Crouching) - 1.20).abs() < f32::EPSILON);
        assert!((config.height(Stance::Prone) - 0.70).abs() < f32::EPSILON);
    }

    #[test]
    fn capsule_half_heights_leave_the_radius_at_the_caps() {
        let config = config();
        assert!((config.half_height(Stance::Standing) - 0.55).abs() < 0.0001);
        assert!((config.half_height(Stance::Crouching) - 0.25).abs() < 0.0001);
        assert!((config.half_height(Stance::Prone) - 0.00).abs() < 0.0001);
    }

    #[test]
    fn eye_offsets_put_the_eye_at_the_stance_height() {
        let config = config();
        for stance in [Stance::Standing, Stance::Crouching, Stance::Prone] {
            let center = config.height(stance) * 0.5;
            let world_eye = center + config.eye_offset(stance);
            assert!((world_eye - config.eye_height(stance)).abs() < 0.0001);
        }
    }

    #[test]
    fn speeds_match_the_measured_package() {
        let config = config();
        assert!((config.speed(Stance::Standing, Gait::Walk) - 5.0).abs() < f32::EPSILON);
        assert!((config.speed(Stance::Standing, Gait::Sprint) - 8.0).abs() < f32::EPSILON);
        assert!((config.speed(Stance::Crouching, Gait::Sprint) - 2.4).abs() < f32::EPSILON);
        assert!((config.speed(Stance::Prone, Gait::Sprint) - 1.2).abs() < f32::EPSILON);
    }
}
