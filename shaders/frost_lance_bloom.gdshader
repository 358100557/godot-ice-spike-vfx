shader_type canvas_item;
render_mode blend_add, unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float threshold : hint_range(0.0, 1.0, 0.01) = 0.82;
uniform float intensity : hint_range(0.0, 1.0, 0.01) = 0.16;


void fragment() {
	vec3 blur_near = textureLod(screen_texture, SCREEN_UV, 1.8).rgb;
	vec3 blur_far = textureLod(screen_texture, SCREEN_UV, 2.8).rgb;
	vec3 blurred = mix(blur_near, blur_far, 0.38);
	float peak = max(blurred.r, max(blurred.g, blurred.b));
	float high_pass = smoothstep(threshold, 1.0, peak);
	COLOR = vec4(blurred * high_pass * intensity, 1.0);
}
