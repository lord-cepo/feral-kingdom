shader_type canvas_item;

uniform vec2 pointer_uv = vec2(-1.0);

void fragment() {
	// Match pointer and fragment in normalized viewport space before measuring rendered pixels.
	float distance_to_pointer = length((SCREEN_UV - pointer_uv) / SCREEN_PIXEL_SIZE);
	float visibility = smoothstep(80.0, 100.0, distance_to_pointer);
	COLOR.a *= visibility;
}
