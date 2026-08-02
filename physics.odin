package main
import "core:fmt"

physics :: proc(game_state: ^Game_state) {
	entities := &game_state.entities
	player_id := entities.player_id
	player := get_entity(entities, player_id)

	levels := game_state.levels
	current_level_index := game_state.current_level
	current_level := &levels[current_level_index]

	//TODO: optimize, dont check everything, only closest tiles


	loop := time_block(.physics_loop)
	for i: u32 = 0; i < game_state.entities.entity_count; i += 1 {
		entity := &game_state.entities.entities[i]
		if entity.kind != .nil {
			entity.pos += entity.vel
			entity.vel = {}

			for tile, index in current_level.tiles {
				if tile.solid {
					tile_collider := get_tile_collider(u32(index))
					entity_collider := get_entity_collider(entity)

					push, hit := collide_aabb_circle(tile_collider, entity_collider)
					if hit {
						entity.pos += push
					}
				}
			}

			for j: u32 = 0; j < game_state.entities.entity_count; j += 1 {
				if i != j {
					entity_2 := &game_state.entities.entities[j]
					entity_1_collider := get_entity_collider(entity)
					entity_2_collider := get_entity_collider(entity_2)

					push, hit := collide_circle_circle(entity_1_collider, entity_2_collider)
					if hit {
						entity.pos += push / 2
						entity_2.pos -= push / 2
					}
				}
			}
		}
	}
	block_end(loop)


}
