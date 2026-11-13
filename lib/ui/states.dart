import 'package:flutter/material.dart';

import '../services/connection_monitor.dart';

/// Shared empty/loading/error skeleton widgets.
///
/// Theme-derived so they follow
/// the app's dark Material 3 scheme without hardcoding brand colors.
class AppEmptyState extends StatelessWidget {
  /// Creates an empty-state block with an optional caller-provided CTA.
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  /// Icon rendered inside the decorative circle.
  final IconData icon;

  /// Primary heading for the empty state.
  final String title;

  /// Optional supporting copy under the heading.
  final String? subtitle;

  /// Optional call-to-action widget, typically a tonal [FilledButton].
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border:
                    Border.all(color: scheme.onSurface.withValues(alpha: 0.12)),
              ),
              child: Center(
                child: Icon(icon, color: scheme.primary, size: 36),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 13,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Error block with an optional retry CTA.
class AppErrorState extends StatelessWidget {
  /// Creates an error block; pass [onRetry] to show the refresh button.
  const AppErrorState({
    super.key,
    this.title = "That didn't go through",
    this.detail,
    this.onRetry,
  });

  /// Primary heading; brief title text by default.
  final String title;

  /// Optional supporting copy under the heading.
  final String? detail;

  /// Invoked when the refresh button is pressed; null hides the button.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                color: scheme.onSurface.withValues(alpha: 0.55), size: 48),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 13,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact branded spinner for buttons, tiles, and inline waits.
class BroSpinner extends StatelessWidget {
  const BroSpinner({
    super.key,
    this.size = 22,
    this.strokeWidth = 2.4,
    this.color,
  });

  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        color: tint,
        backgroundColor: tint.withValues(alpha: 0.18),
      ),
    );
  }
}

/// Centered screen loader. Prefer [ListSkeleton] / [BubbleSkeleton] /
/// [FormSkeleton] when the destination has a list or form shape.
class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.label});

  final String? label;

  factory AppLoader.standard() => const AppLoader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BroSpinner(size: 28),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(
              label!,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.55),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Soft shine that travels across skeleton placeholders.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            return LinearGradient(
              begin: Alignment(-1.2 + _ctrl.value * 2.4, 0),
              end: Alignment(-0.2 + _ctrl.value * 2.4, 0),
              colors: [
                Colors.white.withValues(alpha: 0.28),
                Colors.white,
                Colors.white.withValues(alpha: 0.28),
              ],
              stops: const [0.2, 0.5, 0.8],
            ).createShader(rect);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Simple list skeleton: circular avatars with two placeholder text bars.
class ListSkeleton extends StatelessWidget {
  /// Creates a list skeleton with the given semantic description.
  const ListSkeleton({super.key, this.label = 'Loading'});

  /// Text announced to screen readers instead of the decoration.
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final block = scheme.onSurface.withValues(alpha: 0.08);
    Widget row() {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: block, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 120,
                    height: 12,
                    decoration: BoxDecoration(
                        color: block, borderRadius: BorderRadius.circular(6)),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: block,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Shimmer(
        child: ListView.builder(
          itemCount: 7,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemBuilder: (context, _) => row(),
        ),
      ),
    );
  }
}

/// Settings / profile placeholder: avatar plus field bars.
class FormSkeleton extends StatelessWidget {
  const FormSkeleton({super.key, this.label = 'Loading'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final block = scheme.onSurface.withValues(alpha: 0.08);
    Widget bar({double width = double.infinity, double height = 48}) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: block,
          borderRadius: BorderRadius.circular(14),
        ),
      );
    }

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Shimmer(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: [
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration:
                    BoxDecoration(color: block, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(height: 28),
            bar(),
            const SizedBox(height: 14),
            bar(),
            const SizedBox(height: 14),
            bar(),
            const SizedBox(height: 22),
            bar(width: 160, height: 12),
            const SizedBox(height: 14),
            bar(),
            const SizedBox(height: 14),
            bar(),
          ],
        ),
      ),
    );
  }
}

/// Chat skeleton: alternating left/right rounded bubble placeholders.
class BubbleSkeleton extends StatelessWidget {
  /// Creates a chat bubble skeleton with the given semantic description.
  const BubbleSkeleton({super.key, this.label = 'Loading messages'});

  /// Text announced to screen readers instead of the decoration.
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final block = scheme.onSurface.withValues(alpha: 0.08);
    Widget bubble(bool mine) {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: block,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(mine ? 18 : 7),
              topRight: Radius.circular(mine ? 7 : 18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 150,
                height: 10,
                decoration: BoxDecoration(
                  color: block,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 200,
                height: 10,
                decoration: BoxDecoration(
                  color: block,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Shimmer(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < 6; i++) ...[
                bubble(i.isEven),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Slim banner shown at the top of the app whenever the device is offline.
///
/// Listens to [ConnectionMonitor.isOnline] and collapses to zero height when
/// connectivity returns, so it never displaces app content.
class OfflineBanner extends StatelessWidget {
  /// Creates the offline connectivity banner.
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectionMonitor.isOnline,
      builder: (context, online, _) {
        return IgnorePointer(
          ignoring: online,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: online
                ? const SizedBox.shrink(key: ValueKey('offline-banner-hidden'))
                : SizedBox(
                    key: const ValueKey('offline-banner-visible'),
                    width: double.infinity,
                    child: Material(
                      color: scheme.errorContainer,
                      elevation: 0,
                      child: SafeArea(
                        top: true,
                        bottom: false,
                        child: Container(
                          height: 44,
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cloud_off,
                                size: 16,
                                color: scheme.onErrorContainer,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "You're offline right now.",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: scheme.onErrorContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}
