package main
import "core:math"
import la "core:math/linalg"
import "vendor:glfw"

cooldown :: proc(value: ^f32, dt: f32) {
	value^ -= dt
	if value^ < 0 {
		value^ = 0
	}
}

input :: proc(window: glfw.WindowHandle, game_state: ^Game_state, renderer: ^Renderer) {
	entities := &game_state.entities
	player_id := entities.player_id
	player := get_entity(entities, player_id)
	dt := game_state.dt


	cooldown(&player.attack_cooldown, f32(dt))

	if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS {
		glfw.SetWindowShouldClose(window, true)
	}

	movement := la.Vector2f32{}
	if glfw.GetKey(window, glfw.KEY_W) == glfw.PRESS {
		movement.y -= 1
	}
	if glfw.GetKey(window, glfw.KEY_S) == glfw.PRESS {
		movement.y += 1
	}
	if glfw.GetKey(window, glfw.KEY_A) == glfw.PRESS {
		movement.x -= 1
	}
	if glfw.GetKey(window, glfw.KEY_D) == glfw.PRESS {
		movement.x += 1
	}

	if glfw.GetMouseButton(window, glfw.MOUSE_BUTTON_1) == glfw.PRESS {
		if player.attack_cooldown <= 0 {
			player.attacking = true
			player.attack_animation = 0.2
			player.attack_cooldown = player.attack_cooldown_max
			//TODO: make more generic, just player attack for now
			particle_burst(game_state, player.pos)
		}
	}


	if glfw.GetKey(window, glfw.KEY_Z) == glfw.PRESS {
		renderer.camera.zoom += 0.1
	}

	if glfw.GetKey(window, glfw.KEY_X) == glfw.PRESS {
		renderer.camera.zoom -= 0.1
	}

	if glfw.GetKey(window, glfw.KEY_C) == glfw.PRESS {
		renderer.camera.manual = true
	}

	mouse_screen_x, mouse_screen_y := glfw.GetCursorPos(window)
	mouse_x, mouse_y := apply_camera(renderer.camera, f32(mouse_screen_x), f32(mouse_screen_y))
	mouse_vec := la.Vector2f32{mouse_x, mouse_y}
	facing_vec := mouse_vec - player.pos
	theta := math.atan2(facing_vec.y, facing_vec.x)
	player.rotation = theta

	if movement.x != 0 && movement.y != 0 {
		movement = la.normalize(movement)
	}

	player.vel = movement * player.speed
}
