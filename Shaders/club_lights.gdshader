shader_type canvas_item;
render_mode blend_add;

/// A handful of soft colored blobs drifting and pulsing over the lower part
/// of the screen, cycling hue slowly -- a cheap stand-in for a club's
/// flashing dance-floor lights. Additive blend means it only ever brightens
/// what's underneath, so it layers on top of the background photo without
/// hiding it, and does nothing (adds black) wherever no light overlaps.

/// Overall pace. Keep this low -- these lights should drift and breathe,
/// not strobe.
uniform float speed : hint_range(0.0, 1.0) = 0.2;
/// How big each glow is, in UV units (0..1 of the node's rect).
uniform float glow_radius : hint_range(0.05, 0.5) = 0.32;
/// How bright the lights get at their peak.
uniform float intensity : hint_range(0.0, 3.0) = 1.6;

// Five fixed anchor points scattered across the lower half (the dance
// floor in the background art sits roughly here), each nudged around a
// little over time rather than sitting dead still.
const int LIGHT_COUNT = 5;

vec3 hue_to_rgb(float h) {
	vec3 c = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return c;
}

void fragment() {
	vec2 positions[LIGHT_COUNT] = vec2[](
		vec2(0.18, 0.72),
		vec2(0.38, 0.85),
		vec2(0.55, 0.68),
		vec2(0.28, 0.92),
		vec2(0.62, 0.82)
	);

	vec3 col = vec3(0.0);

	for (int i = 0; i < LIGHT_COUNT; i++) {
		float t = TIME * speed + float(i) * 1.7;
		vec2 p = positions[i] + vec2(sin(t * 0.6) * 0.04, cos(t * 0.4) * 0.03);

		float d = distance(UV, p);
		// Squaring the falloff gives a brighter, more defined core instead
		// of an even soft smear -- reads more like a stage light, less like
		// a faint haze.
		float glow = pow(smoothstep(glow_radius, 0.0, d), 0.6);
		// Slow breathing pulse, offset per-light so they don't sync up.
		// Floor kept above 0 so a light dims rather than fully vanishing
		// between pulses (sin is -1..1, so this maps to [0.35, 1.0]).
		float pulse = mix(0.35, 1.0, 0.5 + 0.5 * sin(t * 1.1));

		vec3 light_col = hue_to_rgb(fract(t * 0.08 + float(i) * 0.23));
		col += light_col * glow * pulse * intensity;
	}

	COLOR = vec4(col, 1.0);
}
