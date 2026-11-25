import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart' as app_colors;
import '../auth_validation.dart';

/// Lightweight 3-segment strength bar (Weak / Fair / Strong) for password inputs.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    final strength = evaluatePasswordStrength(password);
    final (filledCount, color, label) = switch (strength) {
      PasswordStrength.weak => (1, const Color(0xFFFF8D8D), 'Weak'),
      PasswordStrength.fair => (2, const Color(0xFFFFB74D), 'Fair'),
      PasswordStrength.strong => (3, app_colors.P.success, 'Strong'),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 4,
                decoration: BoxDecoration(
                  color: i < filledCount
                      ? color
                      : app_colors.P.border.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (i < 2) const SizedBox(width: 6),
          ],
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
