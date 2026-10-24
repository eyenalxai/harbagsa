#+vet explicit-allocators
package harness

import "src:game"

Light_State :: struct {
	active:    bool   `json:"active"`,
	color:     string `json:"color"`,
	intensity: f32    `json:"intensity"`,
	range:     f32    `json:"range"`,
}

Light_Budget_State :: struct {
	active: int `json:"active"`,
	lamps:  int `json:"lamps"`,
}

light_state :: proc(settings: game.Light_Settings) -> Light_State {
	if !settings.active {
		return {}
	}
	return {
		active = true,
		color = game.light_color_name(settings.color),
		intensity = settings.intensity,
		range = settings.range,
	}
}

light_budget_state :: proc(sim: ^game.Simulation) -> Light_Budget_State {
	return {
		active = game.simulation_active_light_count(sim),
		lamps = game.simulation_lamp_count(sim),
	}
}
