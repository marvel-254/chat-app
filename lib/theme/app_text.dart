import 'package:flutter/material.dart';

import 'app_colors.dart' as app_colors;

/// Type scale for BRO's auth surfaces, set in Space Grotesk.
///
/// Centralizing these keeps the login and onboarding screens on one rhythm
/// instead of hand-tuned sizes at every callsite. Body copy stays on the
/// platform default font family via the ambient ThemeData.
abstract final class AppText {
  static const fontFamily = 'Space Grotesk';

  /// Heavy BRO letterforms (wordmark, splash).
  static const wordmark = TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w700,
    fontSize: 15,
    height: 1.0,
    letterSpacing: 3.2,
    color: app_colors.P.text,
  );

  /// Largest display style — onboarding hero titles.
  static const displayXL = TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w700,
    fontSize: 42,
    height: 1.0,
    letterSpacing: -1.8,
    color: app_colors.P.text,
  );

  /// Display for compact/short layouts.
  static const displayLG = TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w700,
    fontSize: 33,
    height: 1.02,
    letterSpacing: -1.1,
    color: app_colors.P.text,
  );

  /// Login hero headline.
  static const heroTitle = TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w700,
    fontSize: 28,
    height: 1.02,
    letterSpacing: -0.8,
    color: app_colors.P.text,
  );

  /// Login compact-header headline (short screens / keyboard open).
  static const heroTitleCompact = TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w700,
    fontSize: 26,
    height: 1.05,
    letterSpacing: -0.6,
    color: app_colors.P.text,
  );

  /// Small uppercase eyebrow chip labels.
  static const eyebrow = TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w700,
    fontSize: 9,
    letterSpacing: 1.05,
    color: app_colors.P.muted,
  );

  /// Uppercase field labels above inputs.
  static const fieldLabel = TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w700,
    fontSize: 11,
    letterSpacing: 0.08,
    color: app_colors.P.muted,
  );

  /// Subtitle under display headings.
  static const subtitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    color: app_colors.P.muted,
  );

  /// Body copy at reading size.
  static const body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 1.55,
    color: app_colors.P.muted,
  );

  /// Micro captions (footer, helper lines).
  static const caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    height: 1.35,
    color: app_colors.P.muted,
  );

  /// Button label style.
  static const button = TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w700,
    fontSize: 16,
    letterSpacing: 0.3,
    color: app_colors.P.darkOnAccent,
  );
}
