package main

TILE_W :: 16
TILE_H :: 24
TILE_SCALE :: 3

TILESET_W :: 4096
TILESET_H :: 4080

TILESET_COLS :: TILESET_W / TILE_W
TILESET_ROWS :: TILESET_H / TILE_H

sprite_table: Sprite_table

Sprite :: struct {
	u0, v0, u1, v1: f32,
}

Color :: [4]f32

Rect :: struct {
	x0: f32,
	y0: f32,
	x1: f32,
	y1: f32,
}

Rect_points :: struct {
	x0: f32,
	y0: f32,
	x1: f32,
	y1: f32,
	x2: f32,
	y2: f32,
	x3: f32,
	y3: f32,
}

Circle :: struct {
	x: f32,
	y: f32,
	r: f32,
}

Asset_id :: enum u32 {
	player_1,
	floor,
	demon,
	wall,
	arrow_full,
	arrow_hollow,
}

Sprite_table :: [Asset_id]Sprite


asset_positions := [Asset_id]u32 {
	.player_1     = 1,
	.floor        = 24832,
	.demon        = 24077,
	.wall         = 25600,
	.arrow_full   = 7433,
	.arrow_hollow = 7437,
}

build_sprite_table :: proc() -> [Asset_id]Sprite {
	sprite_table: [Asset_id]Sprite

	for id in Asset_id {
		tile_index := asset_positions[id]
		col := i32(tile_index) % TILESET_COLS
		row := i32(tile_index) / TILESET_COLS

		sprite_table[id] = Sprite {
			u0 = f32(col * TILE_W) / f32(TILESET_W),
			v0 = f32(row * TILE_H) / f32(TILESET_H),
			u1 = f32((col + 1) * TILE_W) / f32(TILESET_W),
			v1 = f32((row + 1) * TILE_H) / f32(TILESET_H),
		}
	}

	return sprite_table
}
