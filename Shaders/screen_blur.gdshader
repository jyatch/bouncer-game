shader_type canvas_item;

/// A gaussian-ish blur of whatever has already been drawn beneath this node
/// (via SCREEN_TEXTURE), used as a full-screen overlay in Main. The
/// "amount" uniform is driven from main.gd, ramped up per club after the
/// first so the screen gets noticeably blurrier with every bouncer change --
/// standing in for the player getting progressively more drunk.
///
/// 25-tap 5x5 grid rather than a tight single ring -- a handful of samples
/// spread far apart just doubles edges instead of reading as blur. This
/// still costs nothing on a single full-screen quad.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
/// Spacing between taps, in screen pixels. 0 = no blur at all. The higher
/// this goes, the wider (and more noticeable) the blur.
uniform float amount : hint_range(0.0, 32.0) = 0.0;

void fragment() {
	vec2 step = SCREEN_PIXEL_SIZE * amount;
	vec4 sum = vec4(0.0);
	float total = 0.0;

	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 offset = vec2(float(x), float(y));
			float w = exp(-dot(offset, offset) / 4.0);
			sum += texture(screen_tex, SCREEN_UV + offset * step) * w;
			total += w;
		}
	}

	COLOR = sum / total;
}
