import 'package:flutter/material.dart';
import '../theme/app_colors.dart' as app_colors;
import 'home_nav_bar.dart';
import '../screens/navigation/nav_sidebar.dart';

/// Shared responsive frame for authenticated BRO surfaces.
///
/// Android and narrow windows get a native app bar plus bottom dock. Wider
/// windows get a persistent navigation rail and a compact workspace header.
class ResponsiveAppShell extends StatelessWidget {
  const ResponsiveAppShell({
    super.key,
    required this.title,
    required this.navIndex,
    required this.body,
    this.subtitle,
    this.actions = const <Widget>[],
    this.floatingActionButton,
    this.leading,
    this.showBottomNavigation = true,
    this.backgroundColor = app_colors.bg,
  });

  final String title;
  final String? subtitle;
  final int navIndex;
  final Widget body;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  final Widget? leading;
  final bool showBottomNavigation;
  final Color backgroundColor;

  static const desktopBreakpoint = 840.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= desktopBreakpoint;
        if (!wide) {
          return Scaffold(
            backgroundColor: backgroundColor,
            appBar: AppBar(
              leading: leading,
              title: Text(title),
              actions: actions,
            ),
            body: body,
            floatingActionButton: floatingActionButton,
            bottomNavigationBar:
                showBottomNavigation ? HomeNavBar(index: navIndex) : null,
          );
        }

        return Scaffold(
          backgroundColor: backgroundColor,
          body: Row(
            children: [
              const NavSidebar(),
              Expanded(
                child: Column(
                  children: [
                    _WorkspaceHeader(
                      title: title,
                      subtitle: subtitle,
                      actions: actions,
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1180),
                          child: SizedBox.expand(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                              child: body,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: floatingActionButton,
        );
      },
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: app_colors.bg,
        border: Border(
          bottom: BorderSide(
            color: app_colors.border.withValues(alpha: 0.28),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: app_colors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: app_colors.muted,
                      fontSize: 12,
                      height: 1.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: actions,
            ),
        ],
      ),
    );
  }
}
