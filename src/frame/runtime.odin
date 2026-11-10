#+vet explicit-allocators
#+vet !unused-procedures // the harness resets the runtime; the game binary does not
package frame

import "core:mem"

import "src:bake"
import "src:game"
import "src:renderer"

// Runtime is the mutable frame state the window loop and the harness share.
Runtime :: struct {
	allocator: mem.Allocator,
	sim:       game.Simulation,
	debug:     game.Debug_Mode,
	hud:       game.HUD_State,
	scratch:   ^Scratch,
}

// Frame_Step is one call of the fixed-step order. The caller owns the
// accumulator and the per-frame look; fixed_steps is the count it resolved.
Frame_Step :: struct {
	fixed_steps: int,
	delta:       f32,
	snapshot:    game.Input_Snapshot,
	motion:      game.Debug_Motion,
	actions:     []game.Edit_Action,
}

// The harness has no pointer capture; keep the editor drag alive across a step.
fixed_step :: proc(snapshot: game.Input_Snapshot) -> Frame_Step {
	return {
		fixed_steps = 1,
		delta = game.SIMULATION_STEP,
		snapshot = snapshot,
		motion = {captured = true},
	}
}

runtime_create :: proc(allocator: mem.Allocator) -> Runtime {
	// The scratch holds the frame's debug lines, so the session keeps it off the
	// stack.
	runtime := Runtime {
		allocator = allocator,
		scratch   = new(Scratch, allocator),
		sim       = game.simulation_create(allocator),
		debug     = game.debug_mode_create(allocator),
	}
	runtime.scratch.allocator = allocator
	return runtime
}

runtime_destroy :: proc(runtime: ^Runtime) {
	if game.simulation_is_valid(&runtime.sim) {
		game.simulation_destroy(&runtime.sim)
	}
	game.debug_mode_destroy(&runtime.debug)
	if runtime.scratch != nil {
		scratch_destroy(runtime.scratch)
		free(runtime.scratch, runtime.allocator)
	}
	runtime^ = {}
}

runtime_is_valid :: proc(runtime: ^Runtime) -> bool {
	return runtime.scratch != nil && game.simulation_is_valid(&runtime.sim)
}

runtime_reset :: proc(runtime: ^Runtime) -> bool {
	displays := runtime.sim.settings.display
	game.menu_reset(&runtime.hud.menu)
	if game.simulation_is_valid(&runtime.sim) {
		game.simulation_destroy(&runtime.sim)
	}
	runtime.sim = game.simulation_create(runtime.allocator)
	if !game.simulation_is_valid(&runtime.sim) {
		return false
	}
	runtime.sim.settings.display = displays
	// The debug mode holds a saved player and editor history from the world that
	// just went away.
	game.debug_mode_destroy(&runtime.debug)
	runtime.debug = game.debug_mode_create(runtime.allocator)
	return true
}

runtime_step :: proc(runtime: ^Runtime, step: Frame_Step) {
	if runtime.hud.menu.open {
		return
	}
	snapshot := step.snapshot
	for _ in 0 ..< step.fixed_steps {
		if runtime.debug.active {
			game.simulation_step_world(&runtime.sim, game.SIMULATION_STEP)
		} else {
			game.simulation_step(&runtime.sim, snapshot, game.SIMULATION_STEP)
			snapshot.jump_pressed = false
			snapshot.sprint_pressed = false
		}
		game.hud_notice_update(&runtime.hud, game.SIMULATION_STEP)
	}
	// Edit after the fixed steps so a dragged transform is the one rendered.
	if runtime.debug.active {
		game.debug_mode_update(
			&runtime.debug,
			&runtime.sim,
			step.motion,
			step.actions,
			runtime.hud.menu.open,
			step.delta,
		)
	}
}

runtime_compose :: proc(
	runtime: ^Runtime,
	options: Options,
	camera_override: ^renderer.Camera,
	bake_static: bake.Static,
) -> renderer.Render_Input {
	return build(
		&runtime.sim,
		&runtime.debug,
		options,
		camera_override,
		&runtime.hud,
		runtime.scratch,
		bake_static,
	)
}
