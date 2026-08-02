package main
import la "core:math/linalg"


LEVEL_W :: 100
LEVEL_H :: 100

Tile :: struct {
	asset_id: Asset_id,
	color:    [4]f32,
	solid:    bool,
}

get_tile_collider :: proc(index: u32) -> Rect {
	tile_pos := get_tile_pos(index)
	pixel_pos := get_tile_pixel_pos(tile_pos)

	return Rect {
		x0 = f32(pixel_pos[0]),
		y0 = f32(pixel_pos[1]),
		x1 = f32(pixel_pos[0] + TILE_W * TILE_SCALE),
		y1 = f32(pixel_pos[1] + TILE_H * TILE_SCALE),
	}
}

get_tile_pos :: proc(index: u32) -> [2]u32 {
	result: [2]u32
	result[0] = index % LEVEL_W
	result[1] = index / LEVEL_W
	return result
}

get_tile_pixel_pos :: proc(pos: [2]u32) -> [2]u32 {
	result: [2]u32
	result[0] = pos[0] * TILE_W * TILE_SCALE
	result[1] = pos[1] * TILE_H * TILE_SCALE
	return result
}

Level :: struct {
	tiles: [LEVEL_W * LEVEL_H]Tile,
}
