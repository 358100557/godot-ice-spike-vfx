shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

uniform vec4 burst_color : source_color = vec4(0.65, 0.90, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.949, 0.996, 1.0, 1.0);
uniform float effect_age : hint_range(0.0, 1.0, 0.001) = 0.0;
uniform float intensity = 0.75;
uniform float opacity = 0.85;
uniform float fresnel_power = 1.3;
uniform float displace = 0.55;
uniform float seed = 0.0;

varying vec3 burst_local;


// Independently designed for this VFX: quantized coordinates, unsigned mixing.
// Retain fractional seeds; take 24 result bits to guarantee a value below 1.0.
float lattice_random_3d(vec3 value) {
	uvec3 coordinate = uvec3(ivec3(floor(value * 256.0)));
	uint mixed = coordinate.x * 1459277413u + coordinate.y * 3472864199u + coordinate.z * 198491317u;
	mixed = mixed ^ (mixed >> 13u);
	mixed = mixed * 1266479903u;
	mixed = mixed ^ (mixed >> 16u);
	mixed = mixed * 2659756219u;
	mixed = mixed ^ (mixed >> 15u);
	return float(mixed >> 8u) * (1.0 / 16777216.0);
}


float noise3(vec3 position) {
	vec3 cell = floor(position);
	vec3 local = fract(position);
	vec3 curve = local * local * (3.0 - 2.0 * local);
	float n000 = lattice_random_3d(cell + vec3(0.0, 0.0, 0.0));
	float n100 = lattice_random_3d(cell + vec3(1.0, 0.0, 0.0));
	float n010 = lattice_random_3d(cell + vec3(0.0, 1.0, 0.0));
	float n110 = lattice_random_3d(cell + vec3(1.0, 1.0, 0.0));
	float n001 = lattice_random_3d(cell + vec3(0.0, 0.0, 1.0));
	float n101 = lattice_random_3d(cell + vec3(1.0, 0.0, 1.0));
	float n011 = lattice_random_3d(cell + vec3(0.0, 1.0, 1.0));
	float n111 = lattice_random_3d(cell + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, curve.x);
	float nx10 = mix(n010, n110, curve.x);
	float nx01 = mix(n001, n101, curve.x);
	float nx11 = mix(n011, n111, curve.x);
	return mix(mix(nx00, nx10, curve.y), mix(nx01, nx11, curve.y), curve.z);
}


float fbm3(vec3 position) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 4; octave++) {
		value += noise3(position) * amplitude;
		position = position * 2.03 + vec3(5.1, 8.3, 3.7);
		amplitude *= 0.5;
	}
	return value / 0.9375;
}


void vertex() {
	burst_local = VERTEX;
	float shell_noise = fbm3(normalize(VERTEX) * 4.6 + vec3(seed * 23.0, effect_age * 2.0, 0.0));
	float displacement = (shell_noise - 0.5) * displace * (1.0 - effect_age) * 0.42;
	VERTEX += NORMAL * displacement;
}


void fragment() {
	float age = clamp(effect_age, 0.0, 1.0);
	float fresnel = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), fresnel_power);
	float shell_noise = fbm3(burst_local * 5.2 + vec3(seed * 31.0));
	float plates = smoothstep(0.52, 0.82, shell_noise);
	float dissolve_threshold = age * 1.08 - 0.12;
	float survive = smoothstep(dissolve_threshold, dissolve_threshold + 0.24, shell_noise);
	float fade = 1.0 - smoothstep(0.35, 1.0, age);
	float alpha = (fresnel * 0.78 + plates * 0.24) * survive * fade * opacity;
	if (alpha < 0.002) {
		discard;
	}

	vec3 color = mix(burst_color.rgb, rim_color.rgb, fresnel);
	ALBEDO = color;
	EMISSION = color * (fresnel * 1.25 + plates * 0.38) * intensity;
	ALPHA = alpha;
}
