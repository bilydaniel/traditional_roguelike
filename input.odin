package main
import "core:math"
import la "core:math/linalg"
import "vendor:glfw"

input :: proc(window: glfw.WindowHandle, game_state: ^Game_state) {
	entities := &game_state.entities
	player_id := entities.player_id
	player := get_entity(entities, player_id)

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
		player.attacking = true
		player.attack_animation = true
	}


	if glfw.GetKey(window, glfw.KEY_Z) == glfw.PRESS {
		game_state.camera.zoom += 0.1
	}

	if glfw.GetKey(window, glfw.KEY_X) == glfw.PRESS {
		game_state.camera.zoom -= 0.1
	}

	mouse_screen_x, mouse_screen_y := glfw.GetCursorPos(window)
	mouse_x, mouse_y := apply_camera(game_state.camera, f32(mouse_screen_x), f32(mouse_screen_y))
	mouse_vec := la.Vector2f32{mouse_x, mouse_y}
	facing_vec := mouse_vec - player.pos
	theta := math.atan2(facing_vec.y, facing_vec.x)
	player.rotation = theta

	if movement.x != 0 && movement.y != 0 {
		movement = la.normalize(movement)
	}

	player.vel = movement * player.speed * f32(game_state.dt)
}
