#+vet explicit-allocators
package renderer

import "src:digest"

SHADER_DIGEST_TEXT: [16]u8
SHADER_DIGEST_READY: bool

// The render digest names the frame inputs, so a shader edit does not change
// it. This digest names the SPIR-V that the binary embedded, so an A/B run can
// tell whether the shader itself moved.
shader_digest :: proc() -> string {
	if !SHADER_DIGEST_READY {
		hash := digest.fnv()
		for bytes in ([?][]byte{
			BOX_VERTEX_SPIRV,
			BOX_FRAGMENT_SPIRV,
			BOX_VIEW_FRAGMENT_SPIRV,
			TAA_VERTEX_SPIRV,
			TAA_FRAGMENT_SPIRV,
			TAA_VIEW_FRAGMENT_SPIRV,
			DEBUG_VERTEX_SPIRV,
			DEBUG_FRAGMENT_SPIRV,
			HUD_VERTEX_SPIRV,
			HUD_FRAGMENT_SPIRV,
		}) {
			digest.write_bytes(&hash, bytes)
			digest.write_bytes(&hash, []u8{0})
		}
		hex := "0123456789abcdef"
		value := hash.value
		for index in 0 ..< 16 {
			nibble := (value >> (u64(15 - index) * 4)) & 0xf
			SHADER_DIGEST_TEXT[index] = hex[int(nibble)]
		}
		SHADER_DIGEST_READY = true
	}
	return string(SHADER_DIGEST_TEXT[:])
}
