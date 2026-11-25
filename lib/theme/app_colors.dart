import 'package:flutter/material.dart';

const bg = Color(0xFF121318);
const surface = Color(0xFF1E1F25);
const surfaceHigh = Color(0xFF292A2F);
const surfaceLow = Color(0xFF0D0E13);
const border = Color(0xFF444932);
const text = Color(0xFFE3E1E9);
const muted = Color(0xFFC5C9AC);
const success = Color(0xFF22C55E);

// Electric Street accents
const volt = Color(0xFFD4FF00); // primary accent (lime)
const darkOnVolt = Color(0xFF0C0D12); // text on lime accents

const adaptiveBreakpoint = 600.0;
const desktopBreakpoint = 960.0;

/// Responsive layout tiers for Android/mobile, tablet, and desktop web views.
enum ScreenSizeClass { compact, tablet, desktop }

/// Returns the [ScreenSizeClass] for a given viewport or layout [width].
ScreenSizeClass screenSizeClassForWidth(double width) {
  if (width >= desktopBreakpoint) return ScreenSizeClass.desktop;
  if (width >= adaptiveBreakpoint) return ScreenSizeClass.tablet;
  return ScreenSizeClass.compact;
}

const chatBackgroundOptions = <(String, String, List<Color>)>[
  ('default', 'Night', [bg, surfaceLow]),
  ('ocean', 'Ocean', [Color(0xFF102438), Color(0xFF0D1724)]),
  ('forest', 'Forest', [Color(0xFF142A24), Color(0xFF0E1B19)]),
  ('plum', 'Plum', [Color(0xFF2A1D35), Color(0xFF191521)]),
  ('ember', 'Ember', [Color(0xFF34221B), Color(0xFF1D1715)]),
];

class P {
  static const bg = Color(0xFF121318);
  static const surface = Color(0xFF1E1F25);
  static const surfaceHigh = Color(0xFF292A2F);
  static const surfaceLow = Color(0xFF0D0E13);
  static const border = Color(0xFF444932);
  static const text = Color(0xFFE3E1E9);
  static const muted = Color(0xFFC5C9AC);
  static const success = Color(0xFF22C55E);
  static const primary = Color(0xFFD4FF00);
  static const volt = Color(0xFFD4FF00);
  static const darkOnAccent = Color(0xFF0C0D12);
}

BoxDecoration chatCanvas(String name, {String? imageUrl}) {
  if (imageUrl != null) {
    return BoxDecoration(
        image: DecorationImage(
      image: NetworkImage(imageUrl),
      fit: BoxFit.cover,
      colorFilter: ColorFilter.mode(
          Colors.black.withValues(alpha: 0.28), BlendMode.darken),
    ));
  }
  final option = chatBackgroundOptions.firstWhere((entry) => entry.$1 == name,
      orElse: () => chatBackgroundOptions.first);
  return BoxDecoration(
      gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: option.$3));
}
