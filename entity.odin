package main
import "core:log"
import la "core:math/linalg"

MAX_ENTITIES :: 4096
Entity_id :: u32
Entity_map :: map[Entity_id]u32

//TODO: put this to game_state, wanna not use globals, global for now
//entities: Entities


Entities :: struct {
	entities:       [MAX_ENTITIES]Entity,
	entity_count:   u32,
	last_entity_id: Entity_id,
	id_map:         Entity_map,
	player_id:      Entity_id,
}

init_entities :: proc(entities: ^Entities) {
	entities.id_map = make(Entity_map, MAX_ENTITIES)

	entities.entity_count = 1 // 0 is sentinel
	entities.entities[0].kind = .nil
}

Kind :: enum {
	//TODO: do i want kind or just some flags?
	nil,
	player,
	enemy,
}
Entity :: struct {
	id:           Entity_id, // not sure if needed
	kind:         Kind,
	pos:          la.Vector2f32,
	vel:          la.Vector2f32,
	size:         la.Vector2f32,
	speed:        f32,
	asset_id:     Asset_id,
	color:        [4]f32,
	//TODO: @finish, figure out the position and size of the collider in aseprite
	collider_pos: la.Vector2f32, // relative to pos
	collider_r:   f32,
}

create_entity :: proc(entities: ^Entities, kind: Kind) -> Entity_id {
	result: Entity_id

	if entities.entity_count < MAX_ENTITIES {
		entities.last_entity_id += 1
		id := entities.last_entity_id
		index := entities.entity_count

		new_entity := &entities.entities[index]
		new_entity.kind = kind
		new_entity.id = id

		entities.id_map[id] = index

		entities.entity_count += 1
		result = id
	}

	return result
}
entity_deref :: proc(entities: ^Entities, id: Entity_id) -> u32 {
	//TODO: generation zero?
	result: u32

	index, ok := entities.id_map[id]
	if ok {
		result = index
	} else {
		log.error("wrong id: %v", id)
	}

	return result
}

get_entity :: proc(entities: ^Entities, id: Entity_id) -> ^Entity {
	index := entity_deref(entities, id)
	result_entity: ^Entity = &entities.entities[index]
	if index == 0 {
		log.error("touching sentinel entity")
	}
	return result_entity
}


remove_entity :: proc(entities: ^Entities, id: Entity_id) {
	if entities.entity_count > 1 {
		index := entity_deref(entities, id)
		if index > 0 {
			delete_key(&entities.id_map, id)

			swapped_index := entities.entity_count - 1
			swapped_entity := entities.entities[swapped_index]
			entities.entities[index] = swapped_entity

			entities.id_map[swapped_entity.id] = id

			entities.entities[swapped_index] = {}
			entities.entity_count -= 1
		}
	}
}

spawn_entities :: proc(entities: ^Entities) {
	player_id := create_entity(entities, .player)
	entities.player_id = player_id
	player := get_entity(entities, player_id)

	player.pos = la.Vector2f32{100, 100}
	player.size = la.Vector2f32{TILE_W * TILE_SCALE, TILE_H * TILE_SCALE}
	player.speed = 200
	player.asset_id = .player_1
	player.color = [4]f32{0.8, 0.3, 0.8, 1.0}
	player.collider_pos.x = player.size.x / 2
	player.collider_pos.y = player.size.y - 15
	player.collider_r = 6

	entity1: Entity_id
	entity2: Entity_id

	for i := 2; i < 10; i += 1 {
		entity_id := create_entity(entities, .enemy)
		if i == 2 {
			entity1 = entity_id
		}

		if i == 3 {
			entity2 = entity_id
		}
		entity := get_entity(entities, entity_id)

		entity.pos = la.Vector2f32{f32(i * 50), f32(i * 50)}
		entity.size = la.Vector2f32{TILE_W * TILE_SCALE, TILE_H * TILE_SCALE}
		entity.speed = 200
		entity.asset_id = .demon
		entity.color = [4]f32{0.8, 0.0, 0.0, 1.0}
		entity.collider_pos.x = entity.size.x / 2
		entity.collider_pos.y = entity.size.y - 15
		entity.collider_r = 6
	}

	remove_entity(entities, entity1)
	remove_entity(entities, entity2)

	entity_id := create_entity(entities, .enemy)
	entity := get_entity(entities, entity_id)

	entity.pos = la.Vector2f32{f32(2 * 50), f32(2 * 50)}
	entity.size = la.Vector2f32{TILE_W * TILE_SCALE, TILE_H * TILE_SCALE}
	entity.speed = 200
	entity.asset_id = .demon
	entity.color = [4]f32{0.8, 0.0, 0.0, 1.0}

}

get_entity_collider :: proc(entity: ^Entity) -> Circle {
	x := entity.pos.x + entity.collider_pos.x
	y := entity.pos.y + entity.collider_pos.y
	result := Circle {
		x = x,
		y = y,
		r = entity.collider_r,
	}

	return result
}

collide_aabb_circle :: proc(rect: Rect, circle: Circle) -> (la.Vector2f32, bool) {
	hit: bool
	push: la.Vector2f32

	circle_center := la.Vector2f32{circle.x, circle.y}
	rect_center := la.Vector2f32{rect.x + rect.w / 2, rect.y + rect.h / 2}

	d := circle_center - rect_center
	aabb_half := la.Vector2f32{rect.w / 2, rect.h / 2}

	clamped_x := clamp(d.x, -aabb_half.x, aabb_half.x)
	clamped_y := clamp(d.y, -aabb_half.y, aabb_half.y)

	closest_point := rect_center + la.Vector2f32{clamped_x, clamped_y}

	diff := circle_center - closest_point
	dist := la.length(diff)

	if dist < circle.r {
		normal: la.Vector2f32
		penetration: f32

		if dist == 0 {
			dx := aabb_half.x - abs(d.x)
			dy := aabb_half.y - abs(d.y)
			if dx < dy {
				normal = {1 if d.x > 0 else -1, 0}
				penetration = circle.r + dx
			} else {
				normal = {0, 1 if d.y > 0 else -1}
				penetration = circle.r + dy
			}
		} else {
			normal = diff / dist
			penetration = circle.r - dist
		}
		hit = true
		push = normal * penetration
	}


	return push, hit
}

collide_circle_circle :: proc(a: Circle, b: Circle) -> (la.Vector2f32, bool) {
	hit: bool
	push: la.Vector2f32

	pos_a := la.Vector2f32{a.x, a.y}
	pos_b := la.Vector2f32{b.x, b.y}

	diff := pos_a - pos_b
	dist := la.distance(pos_a, pos_b)
	r_sum := a.r + b.r

	if dist <= r_sum {
		normal: la.Vector2f32
		penetration: f32
		if dist == 0 {
			normal = {1.0, 0} //TODO: probably should do random
		} else {
			normal = diff / dist
		}
		penetration = r_sum - dist
		hit = true
		push = normal * penetration
	}


	return push, hit
}
