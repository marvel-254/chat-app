import 'package:flutter/material.dart';
import '../theme/app_colors.dart' as app_colors;
import 'home_nav_bar.dart';
import '../screens/navigation/nav_sidebar.dart';

/// Shared responsive frame for authenticated BRO surfaces.
///
/// Android and narrow windows (< 600 px) get a native app bar plus bottom
/// dock. Tablets (600–959 px) get a compact 76 px navigation rail, and desktop
/// windows (>= 960 px) get the full 240 px sidebar and workspace header.
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

  static const tabletBreakpoint = app_colors.adaptiveBreakpoint;
  static const desktopBreakpoint = app_colors.desktopBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sizeClass = app_colors.screenSizeClassForWidth(constraints.maxWidth);
        if (sizeClass == app_colors.ScreenSizeClass.compact) {
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

        final isTablet = sizeClass == app_colors.ScreenSizeClass.tablet;
        final contentMaxWidth = isTablet ? 860.0 : 1180.0;
        final contentPadding = isTablet
            ? const EdgeInsets.fromLTRB(16, 0, 16, 16)
            : const EdgeInsets.fromLTRB(24, 0, 24, 24);

        return Scaffold(
          backgroundColor: backgroundColor,
          body: Row(
            children: [
              NavSidebar(compact: isTablet),
              Expanded(
                child: Column(
                  children: [
                    WorkspaceHeader(
                      leading: leading,
                      title: title,
                      subtitle: subtitle,
                      actions: actions,
                      horizontalPadding: isTablet ? 16 : 24,
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: contentMaxWidth),
                          child: SizedBox.expand(
                            child: Padding(
                              padding: contentPadding,
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

class WorkspaceHeader extends StatelessWidget {
  const WorkspaceHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actions,
    this.leading,
    this.horizontalPadding = 24,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 68),
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 12),
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
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
