shader_type canvas_item;
uniform bool unavailable = false;
void fragment() {
	if (unavailable) {
		float grey = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
		COLOR.rgb = vec3(grey);
	}
}
