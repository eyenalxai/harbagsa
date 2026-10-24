#+vet explicit-allocators
#+vet !unused-procedures // the harness reads this; the game binary does not
package digest

import "core:fmt"
import "core:mem"

// FNV-1a. The state digest compares simulation runs, so this algorithm is part
// of the harness contract and must not change.
FNV :: struct {
	value: u64,
}

FNV_OFFSET_BASIS :: 0xcbf29ce484222325
FNV_PRIME :: 0x100000001b3

fnv :: proc() -> FNV {
	return {value = FNV_OFFSET_BASIS}
}

write_u64 :: proc(hash: ^FNV, value: u64) {
	for shift: u64; shift < 8; shift += 1 {
		hash.value = (hash.value ~ (value >> (shift * 8))) * FNV_PRIME
	}
}

write_u32 :: proc(hash: ^FNV, value: u32) {
	write_u64(hash, u64(value))
}

write_i64 :: proc(hash: ^FNV, value: i64) {
	write_u64(hash, u64(value))
}

write_bool :: proc(hash: ^FNV, value: bool) {
	write_u64(hash, value ? 1 : 0)
}

write_f32 :: proc(hash: ^FNV, value: f32) {
	write_u64(hash, u64(transmute(u32)value))
}

write_string :: proc(hash: ^FNV, text: string) {
	for byte in text {
		hash.value = (hash.value ~ u64(byte)) * FNV_PRIME
	}
}

// A string loop iterates runes; pixel data must hash every byte.
write_bytes :: proc(hash: ^FNV, bytes: []u8) {
	for byte in bytes {
		hash.value = (hash.value ~ u64(byte)) * FNV_PRIME
	}
}

hex :: proc(hash: FNV, allocator: mem.Allocator) -> string {
	return fmt.aprintf("%016x", hash.value, allocator = allocator)
}
