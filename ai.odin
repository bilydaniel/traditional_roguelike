package main
import la "core:math/linalg"
import "core:math/rand"

ai :: proc(game_state: ^Game_state) {
	entities := &game_state.entities
	game_state.spawn_time -= game_state.dt
	if game_state.spawn_time <= 0 {
		for i: u32 = 0; i < 10; i += 1 {
			new_id := create_entity(entities, .enemy)
			new_entity := get_entity(entities, new_id)
			new_entity.pos = la.Vector2f32{rand.float32_range(0, 200), rand.float32_range(0, 200)}
			new_entity.size = la.Vector2f32{TILE_W, TILE_H}
			new_entity.speed = 100
			new_entity.asset_id = .demon
			new_entity.color = [4]f32{0.8, 0.0, 0.0, 1.0}
			new_entity.collider_pos.x = new_entity.size.x / 2
			new_entity.collider_pos.y = new_entity.size.y - 6
			new_entity.collider_r = 6
			new_entity.hp = 20
			new_entity.attack = 5

		}
		game_state.spawn_time = game_state.spawn_time_max
	}
	player_id := entities.player_id
	player := get_entity(entities, player_id)

	for i: u32 = 1; i < entities.entity_count; i += 1 {
		entity := &entities.entities[i]
		diff := player.pos - entity.pos
		if diff != 0 {
			dist := la.length(diff)
			normal := la.normalize(diff)

			//TODO: add a stun, and a second vector for knockback
			//entity.vel = normal * entity.speed
			if dist > 100 {
				entity.vel = normal * entity.speed
			}
		}

	}
}
