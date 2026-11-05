shader_type canvas_item;

uniform float inactive_amount : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D previous_pose : source_color, filter_nearest, repeat_disable;
uniform vec2 previous_size = vec2(64.0);
uniform vec2 current_size = vec2(64.0);
uniform vec4 current_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 previous_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 pose_offset_delta = vec2(0.0);
uniform float facing_mix : hint_range(0.0, 1.0) = 1.0;
uniform int bash_side = 0;
uniform float bash_reveal : hint_range(-1.0, 1.0) = 0.0;
uniform float bash_opacity : hint_range(0.0, 1.0) = 1.0;
varying vec4 sprite_tint;
varying float character_x;
void vertex() {
	sprite_tint = COLOR;
	// All 64px frames grow to 1.5x around the unchanged bottom-center anchor.
	VERTEX = (VERTEX - vec2(0.0, 32.0)) * 1.5 + vec2(0.0, 32.0);
	character_x = VERTEX.x;
}

void fragment() {
	// Both Bash actors share the hex center; reveal slides their common half-plane boundary.
	if (bash_side != 0 && bash_reveal < 0.999) {
		if (bash_side < 0 && character_x > bash_reveal * 64.0) discard;
		if (bash_side > 0 && character_x < -bash_reveal * 64.0) discard;
	}
	vec4 pose = texture(TEXTURE, UV);
	if (facing_mix < 1.0) {
		// Translate each silhouette to the same feet, even when its transparent canvas differs.
		vec2 local_uv = (UV - current_region.xy) / current_region.zw;
		vec2 old_uv = ((local_uv - vec2(0.5)) * current_size + pose_offset_delta) / previous_size + vec2(0.5);
		vec4 old_pose = vec4(0.0);
		if (all(greaterThanEqual(old_uv, vec2(0.0))) && all(lessThanEqual(old_uv, vec2(1.0)))) {
			old_pose = texture(previous_pose, previous_region.xy + old_uv * previous_region.zw);
		}
		// Blend premultiplied colors so transparent pixels cannot add dark fringes or double opacity.
		vec4 blended = mix(vec4(old_pose.rgb * old_pose.a, old_pose.a), vec4(pose.rgb * pose.a, pose.a), facing_mix);
		pose = vec4(blended.rgb / max(blended.a, 0.00001), blended.a);
	}
	COLOR = pose * sprite_tint;
	COLOR.a *= bash_opacity;
	float luminance = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	COLOR.rgb = mix(COLOR.rgb, vec3(luminance), smoothstep(0.0, 1.0, inactive_amount));
}
