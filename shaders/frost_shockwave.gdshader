shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

uniform vec4 color_inner : source_color = vec4(0.373, 0.816, 1.0, 1.0);
uniform vec4 color_outer : source_color = vec4(0.949, 0.996, 1.0, 1.0);
uniform float effect_age : hint_range(0.0, 1.0, 0.001) = 0.0;
uniform float maximum_radius = 5.5;
uniform float ring_width = 0.06;
uniform float intensity = 0.9;


void fragment() {
	vec2 point = UV * 2.0 - 1.0;
	float radial = length(point);
	float age = clamp(effect_age, 0.0, 1.0);
	float ring_radius = pow(age, 0.55) * 0.965;
	float normalized_width = max(ring_width / max(maximum_radius, 0.001), 0.0025);
	float antialias = max(fwidth(radial) * 1.4, 0.0015);
	float distance_to_ring = abs(radial - ring_radius);
	float ring = 1.0 - smoothstep(normalized_width, normalized_width + antialias, distance_to_ring);

	float secondary_radius = max(0.0, ring_radius - normalized_width * 3.2);
	float secondary = 1.0 - smoothstep(
		normalized_width * 0.55,
		normalized_width * 0.55 + antialias,
		abs(radial - secondary_radius)
	);
	float fade = pow(max(0.0, 1.0 - age), 1.15);
	vec3 color = mix(color_inner.rgb, color_outer.rgb, smoothstep(0.0, 1.0, radial));
	float alpha = (ring + secondary * 0.24) * fade * intensity;
	if (alpha < 0.001) {
		discard;
	}

	ALBEDO = color;
	EMISSION = color * intensity;
	ALPHA = alpha;
}
