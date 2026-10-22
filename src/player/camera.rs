use bevy::prelude::*;
use bevy::window::PrimaryWindow;

use super::{PlayerCamera, PlayerConfig};

pub fn update_projection(
    config: Res<PlayerConfig>,
    windows: Query<&Window, With<PrimaryWindow>>,
    mut camera: Query<&mut Projection, With<PlayerCamera>>,
) {
    let Ok(window) = windows.single() else {
        return;
    };
    let height = window.height();
    if height <= 0.0 {
        return;
    }

    let aspect = window.width() / height;
    let Ok(mut projection) = camera.single_mut() else {
        return;
    };
    let Projection::Perspective(perspective) = &mut *projection else {
        return;
    };

    perspective.fov = vertical_fov(config.horizontal_fov_degrees, aspect);
    perspective.near = config.near_plane;
}

pub fn vertical_fov(horizontal_degrees: f32, aspect: f32) -> f32 {
    let half_horizontal = horizontal_degrees.to_radians() * 0.5;
    2.0 * (half_horizontal.tan() / aspect).atan()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ninety_degrees_horizontal_is_about_fifty_nine_vertical_at_sixteen_by_nine() {
        let fov = vertical_fov(90.0, 16.0 / 9.0).to_degrees();
        assert!((fov - 58.72).abs() < 0.1);
    }

    #[test]
    fn a_square_window_keeps_ninety_degrees() {
        let fov = vertical_fov(90.0, 1.0).to_degrees();
        assert!((fov - 90.0).abs() < 0.001);
    }
}
