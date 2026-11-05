shader_type canvas_item;

uniform sampler2D previous_pose : source_color, filter_nearest, repeat_disable;
uniform vec2 current_size = vec2(64.0);
uniform vec2 previous_size = vec2(64.0);
uniform vec4 current_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 previous_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform float current_foot = 64.0;
uniform float previous_foot = 64.0;
uniform float facing_mix : hint_range(0.0, 1.0) = 1.0;
uniform float greyscale : hint_range(0.0, 1.0) = 0.0;
varying vec4 portrait_tint;

void vertex() {
	portrait_tint = COLOR;
}

void fragment() {
	vec4 pose = texture(TEXTURE, UV);
	if (facing_mix < 1.0) {
		vec2 pixel = ((UV - current_region.xy) / current_region.zw) * current_size;
		vec2 old_uv = (pixel + vec2((previous_size.x - current_size.x) * 0.5, previous_foot - current_foot)) / previous_size;
		vec4 old_pose = vec4(0.0);
		if (all(greaterThanEqual(old_uv, vec2(0.0))) && all(lessThanEqual(old_uv, vec2(1.0)))) {
			old_pose = texture(previous_pose, previous_region.xy + old_uv * previous_region.zw);
		}
		// One premultiplied blend keeps overlapping opaque pixels opaque instead of dimming twice each turn step.
		vec4 blended = mix(vec4(old_pose.rgb * old_pose.a, old_pose.a), vec4(pose.rgb * pose.a, pose.a), facing_mix);
		pose = vec4(blended.rgb / max(blended.a, 0.00001), blended.a);
	}
	pose.rgb = mix(pose.rgb, vec3(dot(pose.rgb, vec3(0.299, 0.587, 0.114))), greyscale);
	COLOR = pose * portrait_tint;
}
