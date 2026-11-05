shader_type canvas_item;
render_mode unshaded;

// PixelLab's empty map cells export as opaque #1e1e22; reveal the grass underneath.
void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	if (distance(pixel.rgb, vec3(30.0, 30.0, 34.0) / 255.0) < 0.002) {
		COLOR.a = 0.0;
	}
}
