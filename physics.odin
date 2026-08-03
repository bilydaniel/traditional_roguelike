package main
import "core:fmt"
import "core:math"
import la "core:math/linalg"

physics :: proc(game_state: ^Game_state) {
	entities := &game_state.entities
	player_id := entities.player_id
	player := get_entity(entities, player_id)

	levels := game_state.levels
	current_level_index := game_state.current_level
	current_level := &levels[current_level_index]

	//TODO: optimize, dont check everything, only closest tiles

	//TODO: separate file where i evaluate combat?
	if player.attacking {

		for i: u32 = 0; i < game_state.entities.entity_count; i += 1 {
			entity := &game_state.entities.entities[i]
			if entity.id != player.id {
				player_collider := get_entity_collider(player)
				entity_collider := get_entity_collider(entity)
				player_collider_pos := la.Vector2f32{player_collider.x, player_collider.y}
				entity_collider_pos := la.Vector2f32{entity_collider.x, entity_collider.y}
				dist := abs(la.distance(entity_collider_pos, player_collider_pos))
				dist -= (entity.collider_r + player.collider_r)
				if dist <= player.attack_range {
					player_entity_vec := entity_collider_pos - player_collider_pos
					player_entity_angle := math.atan2(player_entity_vec.y, player_entity_vec.x)
					start_attack_angle := player.rotation - player.attack_angle / 2
					end_attack_angle := player.rotation + player.attack_angle / 2
					if player_entity_angle >= start_attack_angle &&
					   player_entity_angle <= end_attack_angle {
						//TODO: @test @finish
						//TODO: take size of the enitty into considaration, probably compoare against the collider?
						fmt.printf("entity_hit\n")
					}

				}
			}
		}
		player.attacking = false
	}

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
