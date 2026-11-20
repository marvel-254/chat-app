import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart' as app_colors;
import '../../../theme/app_text.dart';

/// The BRO wordmark: a tilted volt tile + heavy BRO letterforms.
///
/// Shared by the onboarding, login, confirmation and auth-gate splash
/// surfaces so the brand mark never drifts between entry points.
class BroWordmark extends StatelessWidget {
  const BroWordmark({super.key, this.fontSize = 15});

  /// Size of the "BRO" letterforms; the tile scales with it.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final tile = fontSize * 0.87;
    return ExcludeSemantics(
      // decorative mark; the adjacent text carries the meaning
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.rotate(
            angle: -0.15,
            child: Container(
              width: tile,
              height: tile,
              decoration: BoxDecoration(
                color: app_colors.P.primary,
                borderRadius: BorderRadius.circular(tile * 0.31),
                boxShadow: [
                  BoxShadow(
                    color: app_colors.P.primary.withValues(alpha: 0.22),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: fontSize * 0.66),
          Text(
            'BRO',
            style: AppText.wordmark.copyWith(
              fontSize: fontSize,
              letterSpacing: fontSize * 0.21,
            ),
          ),
        ],
      ),
    );
  }
}
