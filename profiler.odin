package main

import "base:intrinsics"
import "core:fmt"
import "core:sys/posix"

PROFILER_ENABLED :: true

profiler: Profiler
current_parent: Anchor_ID = .unknown

Anchor_ID :: enum {
	unknown,
	main,
	update,
	draw,
	sleep,
}

Profiler :: struct {
	anchors:   [Anchor_ID]Anchor,
	start_tsc: i64,
	end_tsc:   i64,
}

Anchor :: struct {
	tsc_elapsed_exclusive: i64, // excludes the children
	tsc_elapsed_inclusive: i64, // includes the children
	hit_count:             u64,
	processed_byte_count:  u64,
}

Block :: struct {
	start_tsc:                 i64,
	parent_index:              Anchor_ID,
	anchor_index:              Anchor_ID,
	old_tsc_elapsed_inclusive: i64, // fixes wrong measurements of recursive calls
}


time_function :: proc(id: Anchor_ID) -> Block {
	return time_block(id)
}

time_block :: proc(id: Anchor_ID) -> Block {
	return time_block_bandwidth(id, 0)
}

time_block_bandwidth :: proc(id: Anchor_ID, byte_count: u64) -> Block {
	when !PROFILER_ENABLED {
		return Block{}
	}

	return block_start(id, byte_count)
}

block_start :: proc(anchor_index: Anchor_ID, byte_count: u64) -> Block {
	anchor := &profiler.anchors[anchor_index]
	anchor.processed_byte_count += byte_count

	block := Block {
		parent_index              = current_parent,
		anchor_index              = anchor_index,
		start_tsc                 = i64(read_cpu_timer()),
		old_tsc_elapsed_inclusive = anchor.tsc_elapsed_inclusive,
	}
	current_parent = anchor_index
	return block
}

block_end :: proc(b: Block) {
	when !PROFILER_ENABLED {
		return
	}

	elapsed := i64(read_cpu_timer()) - b.start_tsc

	current_parent = b.parent_index

	// exclude the child's time
	parent_anchor := &profiler.anchors[b.parent_index]
	parent_anchor.tsc_elapsed_exclusive -= elapsed

	anchor := &profiler.anchors[b.anchor_index]
	anchor.tsc_elapsed_exclusive += elapsed
	anchor.tsc_elapsed_inclusive = b.old_tsc_elapsed_inclusive + elapsed
	anchor.hit_count += 1
}

begin_profile :: proc() {
	profiler = Profiler{}
	profiler.start_tsc = i64(read_cpu_timer())
}

end_profile :: proc() {
	profiler.end_tsc = i64(read_cpu_timer())
	cpu_freq := estimate_cpu_timer_freq()

	total_elapsed := profiler.end_tsc - profiler.start_tsc

	if cpu_freq > 0 {
		fmt.printf(
			"Total time: %.4fms (%d)\n",
			1000 * f64(total_elapsed) / f64(cpu_freq),
			cpu_freq,
		)
	}

	for anchor, index in profiler.anchors {
		if anchor.tsc_elapsed_inclusive > 0 {
			print_time_elapsed(anchor, total_elapsed, cpu_freq, index)
		}
	}
}

print_time_elapsed :: proc(a: Anchor, total_elapsed: i64, cpu_freq: u64, label: Anchor_ID) {
	percent := 100 * f64(a.tsc_elapsed_exclusive) / f64(total_elapsed)
	fmt.printf(
		"\t%s[%d]: %d(%.2f%%) - %.4fms",
		label,
		a.hit_count,
		a.tsc_elapsed_exclusive,
		percent,
		1000 * f64(a.tsc_elapsed_exclusive) / f64(cpu_freq),
	)

	if a.tsc_elapsed_exclusive != a.tsc_elapsed_inclusive {
		percent_inclusive := 100 * f64(a.tsc_elapsed_inclusive) / f64(total_elapsed)
		fmt.printf("\n\t\t(%.2f%%) with children", percent_inclusive)
	}

	if a.processed_byte_count > 0 {
		megabyte: f64 = 1024 * 1024
		gigabyte: f64 = megabyte * 1024

		seconds := f64(a.tsc_elapsed_inclusive) / f64(cpu_freq)
		bytes_per_second := f64(a.processed_byte_count) / seconds
		megabytes := f64(a.processed_byte_count) / megabyte
		gigabytes_per_second := bytes_per_second / gigabyte
		fmt.printf("\n\t\t%.3fmb at %.2fgb/s", megabytes, gigabytes_per_second)
	}
	fmt.printf("\n")
}

read_cpu_timer :: proc "contextless" () -> u64 {
	return u64(intrinsics.read_cycle_counter())
}

read_os_timer :: proc() -> u64 {
	value: posix.timeval
	posix.gettimeofday(&value, nil)
	return 1_000_000 * u64(value.tv_sec) + u64(value.tv_usec)
}

read_os_page_fault_count :: proc() -> u64 {
	usage: posix.rusage
	posix.getrusage(.SELF, &usage)
	return u64(usage.ru_minflt + usage.ru_majflt)
}

estimate_cpu_timer_freq :: proc() -> u64 {
	MILLISECONDS_TO_WAIT :: 100
	OS_FREQ :: 1_000_000

	cpu_start := read_cpu_timer()
	os_start := read_os_timer()

	os_end: u64 = 0
	os_elapsed: u64 = 0
	os_wait_time: u64 = OS_FREQ * MILLISECONDS_TO_WAIT / 1000

	for os_elapsed < os_wait_time {
		os_end = read_os_timer()
		os_elapsed = os_end - os_start
	}

	cpu_end := read_cpu_timer()
	cpu_elapsed := cpu_end - cpu_start

	cpu_freq: u64 = 0
	if os_elapsed != 0 {
		cpu_freq = OS_FREQ * cpu_elapsed / os_elapsed
	}

	return cpu_freq
}
