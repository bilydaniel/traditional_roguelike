package main
import "core:fmt"
import "core:log"
import "core:math"
import la "core:math/linalg"
import "core:math/rand"

MAX_PARTICLES :: 4096

Particles :: struct {
	particles:      [MAX_PARTICLES]Particle,
	particle_count: u32,
}

//TODO: do i want kinds of particles?
// circles or squares?
Particle :: struct {
	pos:      la.Vector2f32,
	vel:      la.Vector2f32,
	rotation: f32,
	size:     la.Vector2f32,
	color:    [4]f32,
	ttl:      f32,
}

particle_burst :: proc(game_state: ^Game_state, pos: la.Vector2f32) {
	fmt.println("particle_burst")

	particles := &game_state.particles.particles
	particle_count := &game_state.particles.particle_count
	num_of_particles: u32 = 50
	size := la.Vector2f32{3, 3}
	r: f32 = f32(math.sin(game_state.dt))
	g: f32 = 0.0
	b: f32 = f32(math.cos(game_state.dt))
	a: f32 = 1.0

	color: [4]f32 = {r, g, b, a}

	for i: u32; i < num_of_particles; i += 1 {
		if (particle_count^ < MAX_PARTICLES) {
			direction_x := rand.float32_range(-1, 1)
			direction_y := rand.float32_range(-1, 1)
			normalized := la.normalize([2]f32{direction_x, direction_y})
			speed: f32 = 200

			velocity := normalized * speed
			vel := velocity
			particles[particle_count^] = Particle{pos, vel, 0, size, color, 10}
			particle_count^ += 1
		}

	}
}


remove_particle :: proc(particles: ^Particles, index: u32) {
	if particles.particle_count > 0 {
		swapped_index := particles.particle_count - 1
		swapped_particle := particles.particles[swapped_index]
		particles.particles[index] = swapped_particle
		particles.particles[swapped_index] = {}
		particles.particle_count -= 1
	}
}
