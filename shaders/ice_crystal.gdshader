shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 color_ice : source_color = vec4(0.541, 0.855, 1.0, 1.0);
uniform vec4 color_deep : source_color = vec4(0.243, 0.451, 0.478, 1.0);
uniform vec4 color_rim : source_color = vec4(0.949, 0.996, 1.0, 1.0);
uniform vec4 color_core : source_color = vec4(0.388, 0.529, 0.592, 1.0);

uniform float fresnel_strength : hint_range(0.0, 5.0, 0.01) = 2.3;
uniform float fresnel_power : hint_range(0.1, 8.0, 0.05) = 2.4;
uniform float fracture_strength : hint_range(0.0, 2.0, 0.01) = 0.62;
uniform float fracture_scale : hint_range(0.1, 24.0, 0.1) = 6.5;
uniform float veins_strength : hint_range(0.0, 2.0, 0.01) = 0.45;
uniform float veins_scale : hint_range(0.1, 16.0, 0.1) = 3.2;
uniform float frost_line_strength : hint_range(0.0, 2.0, 0.01) = 0.5;
uniform float glow_strength : hint_range(0.0, 4.0, 0.01) = 0.85;
uniform float birth_glow_strength : hint_range(0.0, 6.0, 0.01) = 1.6;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 0.92;
uniform float glint_strength : hint_range(0.0, 4.0, 0.01) = 1.1;
uniform float glint_scale : hint_range(1.0, 80.0, 0.5) = 34.0;
uniform float glint_speed : hint_range(0.0, 4.0, 0.01) = 0.7;

varying vec3 ice_local_position;
varying vec3 ice_world_position;
varying float ice_seed;
varying float ice_birth;


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
	float nxy0 = mix(nx00, nx10, curve.y);
	float nxy1 = mix(nx01, nx11, curve.y);
	return mix(nxy0, nxy1, curve.z);
}


float fbm3(vec3 position) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 4; octave++) {
		value += noise3(position) * amplitude;
		position = position * 2.03 + vec3(7.1, 3.7, 5.9);
		amplitude *= 0.5;
	}
	return value / 0.9375;
}


void vertex() {
	ice_local_position = VERTEX;
	ice_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ice_seed = INSTANCE_CUSTOM.r * 10.0;
	ice_birth = INSTANCE_CUSTOM.g;
}


void fragment() {
	vec3 view_normal = normalize(NORMAL);
	float ndv = abs(dot(view_normal, normalize(VIEW)));
	float rim = pow(clamp(1.0 - ndv, 0.0, 1.0), fresnel_power);
	float thickness = clamp(ndv * 1.15, 0.0, 1.0);

	vec3 fracture_position = ice_world_position * fracture_scale + vec3(ice_seed * 37.0);
	float fracture_field = fbm3(fracture_position);
	float fracture_ridge = 1.0 - abs(fracture_field * 2.0 - 1.0);
	float fracture = smoothstep(0.91, 0.985, fracture_ridge);
	fracture *= smoothstep(0.18, 0.72, noise3(fracture_position * 0.43 + vec3(9.0)));

	vec3 vein_position = vec3(
		ice_local_position.x * veins_scale * 2.4,
		ice_local_position.y * veins_scale * 0.75,
		ice_local_position.z * veins_scale * 2.4
	) + vec3(ice_seed * 11.0);
	float vein_field = fbm3(vein_position);
	float vein_ridge = 1.0 - abs(vein_field * 2.0 - 1.0);
	float veins = smoothstep(0.82, 0.96, vein_ridge);
	veins *= 0.55 + 0.45 * noise3(vein_position * 0.65 + vec3(4.0));

	float base_mask = 1.0 - smoothstep(0.05, 0.55, ice_local_position.y);
	float rime_noise = 0.52 + 0.48 * fbm3(ice_local_position * 9.0 + vec3(ice_seed * 5.0));
	float rime = clamp(base_mask * rime_noise, 0.0, 1.0);

	vec3 body = mix(color_ice.rgb, color_deep.rgb, thickness);
	body = mix(body, color_rim.rgb, fracture * fracture_strength * 0.40);
	body = mix(body, color_rim.rgb, veins * veins_strength * 0.24);
	body = mix(body, color_rim.rgb, rime * frost_line_strength);
	body *= mix(0.86, 1.12, ndv);

	vec3 glint_position = ice_world_position * glint_scale;
	glint_position.y += TIME * glint_speed;
	glint_position += vec3(ice_seed * 23.0);
	float glint_noise = noise3(glint_position);
	float glint = pow(smoothstep(0.82, 0.98, glint_noise), 5.0);
	glint *= smoothstep(0.08, 0.78, rim + 0.18);

	vec3 emission = color_rim.rgb * rim * fresnel_strength * 0.48;
	emission += color_core.rgb * fracture * fracture_strength * 0.78;
	emission += color_core.rgb * veins * veins_strength * 0.28;
	emission += color_rim.rgb * rime * frost_line_strength * 0.20;
	emission += color_rim.rgb * glint * glint_strength;
	emission += mix(color_core.rgb, color_rim.rgb, 0.28) * ice_birth * birth_glow_strength;
	emission *= glow_strength;
	emission /= vec3(1.0) + emission * 0.28;

	ALBEDO = body;
	ROUGHNESS = mix(0.22, 0.12, rim);
	METALLIC = 0.0;
	SPECULAR = 0.62;
	EMISSION = emission;
	ALPHA = clamp(opacity * (0.90 + 0.10 * rim) + fracture * 0.04 + rime * 0.025, 0.0, 1.0);
}
