shader_type canvas_item;

uniform bool inactive = false;
uniform bool bash_mode = false;
uniform float target_aspect = 1.5;
uniform float hover_angle_degrees : hint_range(-15.0, 15.0) = 0.0;
uniform int bash_side = 0;
// -1 collapses the opposing half, 0 preserves the split, 1 reveals the focused card.
uniform float bash_reveal : hint_range(-1.0, 1.0) = 0.0;
uniform float bash_opacity : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	float angle = radians(hover_angle_degrees);
	// A 2D projection of a centered vertical-axis rotation, without perspective distortion.
	VERTEX.x *= cos(angle);
}

void fragment() {
	vec2 hex_uv = UV * 2.0 - 1.0;
	if (abs(hex_uv.x) + 0.5 * abs(hex_uv.y) > 1.0) discard;
	if (bash_side < 0 && UV.x > 0.5 + 0.5 * bash_reveal) discard;
	if (bash_side > 0 && UV.x < 0.5 - 0.5 * bash_reveal) discard;

	float source_aspect = TEXTURE_PIXEL_SIZE.y / TEXTURE_PIXEL_SIZE.x;
	vec2 art_uv = UV;
	if (source_aspect > target_aspect) {
		float visible_width = target_aspect / source_aspect;
		art_uv.x = (UV.x - 0.5) * visible_width + 0.5;
	} else if (source_aspect < target_aspect) {
		float visible_height = source_aspect / target_aspect;
		art_uv.y = (UV.y - 0.5) * visible_height + 0.5;
	}
	vec4 art = texture(TEXTURE, art_uv) * COLOR;
	art.a *= bash_opacity;
	if (inactive) {
		float luminance = dot(art.rgb, vec3(0.299, 0.587, 0.114));
		vec3 parchment_tint = vec3(luminance * 1.18, luminance * 1.08, luminance * 0.72);
		art.rgb = min(mix(art.rgb, parchment_tint, 0.90) * 1.08, vec3(1.0));
		// Guerra changes inactive colour but keeps both Bash halves equally opaque.
		if (!bash_mode) art.a *= 0.62;
	}
	COLOR = art;
}
