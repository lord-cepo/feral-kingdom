// LocalMatchController applies this only to the backing ColorRect, so text stays crisp and opaque.
shader_type canvas_item;
render_mode unshaded;

uniform float feather_pixels : hint_range(1.0, 32.0) = 18.0;

void fragment() {
	vec2 edge_pixels = min(UV, vec2(1.0) - UV) / max(fwidth(UV), vec2(0.00001));
	vec2 edge = clamp(edge_pixels / feather_pixels, vec2(0.0), vec2(1.0));
	// Quintic fades have zero first/second derivatives at both ends; multiplying axes softens corners too.
	vec2 fade = edge * edge * edge * (edge * (edge * 6.0 - 15.0) + 10.0);
	float feather = fade.x * fade.y;
	COLOR.a *= feather;
}
