use bevy::prelude::*;

use super::{InputMode, Player, PlayerConfig, PlayerIntent};

#[derive(Component, Debug, Default)]
pub struct PlayerGaitInput {
    pub sprint_engaged: bool,
    pub sprint_started: bool,
    pub blocked: bool,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct GaitSelection {
    pub sprint_engaged: bool,
}

impl GaitSelection {
    /// Returns true when this update starts a new sprint.
    pub fn update(&mut self, mode: InputMode, pressed: bool, held: bool, blocked: bool) -> bool {
        if mode == InputMode::Toggle && blocked {
            self.sprint_engaged = false;
        }

        let was_engaged = self.sprint_engaged;
        match mode {
            InputMode::Hold => self.sprint_engaged = held,
            InputMode::Toggle => {
                if pressed {
                    self.sprint_engaged = !self.sprint_engaged;
                }
            }
        }

        self.sprint_engaged && !was_engaged
    }
}

pub fn apply_gait_input(
    config: Res<PlayerConfig>,
    intent: Res<PlayerIntent>,
    mut players: Query<&mut PlayerGaitInput, With<Player>>,
) {
    let Ok(mut input) = players.single_mut() else {
        return;
    };

    let mut selection = GaitSelection {
        sprint_engaged: input.sprint_engaged,
    };
    let started = selection.update(
        config.sprint_mode,
        intent.sprint_pressed,
        intent.sprint_held,
        input.blocked,
    );

    input.sprint_engaged = selection.sprint_engaged;
    input.sprint_started = started;
    input.blocked = false;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hold_sprint_is_active_while_held() {
        let mut selection = GaitSelection::default();
        let started = selection.update(InputMode::Hold, true, true, false);
        assert!(selection.sprint_engaged);
        assert!(started);

        let started = selection.update(InputMode::Hold, false, true, false);
        assert!(selection.sprint_engaged);
        assert!(!started);

        let started = selection.update(InputMode::Hold, false, false, false);
        assert!(!selection.sprint_engaged);
        assert!(!started);
    }

    #[test]
    fn toggle_sprint_flips_on_press() {
        let mut selection = GaitSelection::default();
        let started = selection.update(InputMode::Toggle, true, false, false);
        assert!(selection.sprint_engaged);
        assert!(started);

        let started = selection.update(InputMode::Toggle, true, false, false);
        assert!(!selection.sprint_engaged);
        assert!(!started);
    }

    #[test]
    fn a_blocked_toggle_clears_on_the_next_update() {
        let mut selection = GaitSelection::default();
        let started = selection.update(InputMode::Toggle, true, false, false);
        assert!(selection.sprint_engaged);
        assert!(started);

        let started = selection.update(InputMode::Toggle, false, false, true);
        assert!(!selection.sprint_engaged);
        assert!(!started);
    }

    #[test]
    fn a_blocked_hold_keeps_trying() {
        let mut selection = GaitSelection::default();
        let started = selection.update(InputMode::Hold, true, true, true);
        assert!(selection.sprint_engaged);
        assert!(started);
    }
}
