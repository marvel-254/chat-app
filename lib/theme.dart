import 'package:flutter/material.dart';

// BRO palette — Electric Street dark theme (Material 3).
//
// Used across the app via ThemeData.colorScheme so every widget
// derives colors from the scheme instead of hardcoding hex values.
// Keep this file in sync with the colorScheme built in main.dart.

/// App background — near-black with a cool bias.
const bg = Color(0xFF121318);

/// Elevated surfaces (cards, sheets, dialogs).
const surface = Color(0xFF1E1F25);

/// Higher elevation surface for hovered/focused states.
const surfaceHigh = Color(0xFF292A2F);

/// Lower elevation surface for input fields, dividers.
const surfaceLow = Color(0xFF0D0E13);

/// Subtle border/divider tone (olive-green tint per brand).
const border = Color(0xFF444932);

/// Primary text on dark surfaces.
const text = Color(0xFFE3E1E9);

/// Secondary / muted text.
const muted = Color(0xFFC5C9AC);

/// Success green.
const success = Color(0xFF22C55E);

/// Electric-lime primary accent.
const primary = Color(0xFFD4FF00);

/// Text color on top of the primary accent (near-black).
const darkOnPrimary = Color(0xFF0C0D12);

/// ColorScheme seed that reproduces the palette via M3 tonal palettes.
const colorSchemeSeed = Color(0xFFD4FF00);

/// Adaptive breakpoint for tablet/desktop layouts.
const adaptiveBreakpoint = 600.0;

/// Chat background gradient presets.
const chatBackgroundOptions = <(String, String, List<Color>)>[
  ('default', 'Night', [bg, surfaceLow]),
  ('ocean', 'Ocean', [Color(0xFF102438), Color(0xFF0D1724)]),
  ('forest', 'Forest', [Color(0xFF142A24), Color(0xFF0E1B19)]),
  ('plum', 'Plum', [Color(0xFF2A1D35), Color(0xFF191521)]),
  ('ember', 'Ember', [Color(0xFF34221B), Color(0xFF1D1715)]),
];

/// Builds a BoxDecoration for a chat canvas (gradient or image overlay).
BoxDecoration chatCanvasDecoration(String name, {String? imageUrl}) {
  if (imageUrl != null) {
    return BoxDecoration(
      image: DecorationImage(
        image: NetworkImage(imageUrl),
        fit: BoxFit.cover,
        colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.28), BlendMode.darken),
      ),
    );
  }
  final option = chatBackgroundOptions.firstWhere((entry) => entry.$1 == name,
      orElse: () => chatBackgroundOptions.first);
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: option.$3,
    ),
  );
}