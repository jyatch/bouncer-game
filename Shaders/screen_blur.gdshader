shader_type canvas_item;

/// A cheap multi-tap blur of whatever has already been drawn beneath this
/// node (via SCREEN_TEXTURE), used as a full-screen overlay in Main. The
/// "amount" uniform is driven from main.gd, ramped up per club after the
/// first so the screen gets a little blurrier with every bouncer change --
/// standing in for the player getting progressively more drunk.
///
/// Deliberately a small, cheap 3x3 tap pattern rather than a true large-
/// radius gaussian -- the ask is "slight blurriness", not a heavy postFX.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
/// In screen pixels (roughly). 0 = no blur at all.
uniform float amount : hint_range(0.0, 8.0) = 0.0;

void fragment() {
	// No early-out needed: at amount == 0, px is zero, so every tap below
	// samples the same texel and the weighted sum reduces to a plain copy.
	vec2 px = SCREEN_PIXEL_SIZE * amount;
	vec4 sum = vec4(0.0);

	// Tent-weighted 3x3: center counts most, orthogonal neighbors next,
	// diagonals least. Weights add up to 16.
	sum += texture(screen_tex, SCREEN_UV) * 4.0;
	sum += texture(screen_tex, SCREEN_UV + vec2(px.x, 0.0)) * 2.0;
	sum += texture(screen_tex, SCREEN_UV - vec2(px.x, 0.0)) * 2.0;
	sum += texture(screen_tex, SCREEN_UV + vec2(0.0, px.y)) * 2.0;
	sum += texture(screen_tex, SCREEN_UV - vec2(0.0, px.y)) * 2.0;
	sum += texture(screen_tex, SCREEN_UV + px) * 1.0;
	sum += texture(screen_tex, SCREEN_UV - px) * 1.0;
	sum += texture(screen_tex, SCREEN_UV + vec2(px.x, -px.y)) * 1.0;
	sum += texture(screen_tex, SCREEN_UV + vec2(-px.x, px.y)) * 1.0;

	COLOR = sum / 16.0;
}
