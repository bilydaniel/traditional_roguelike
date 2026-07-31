package main
import la "core:math/linalg"

ai :: proc(game_state: ^Game_state) {
	entities := &game_state.entities
	player_id := entities.player_id
	player := get_entity(entities, player_id)

	for &entity in entities.entities {
		diff := player.pos - entity.pos
		dist := la.length(diff)
		normal := la.normalize(diff)
		if dist > 100 {
			entity.vel = normal * entity.speed * f32(game_state.dt)
		}

	}
}
