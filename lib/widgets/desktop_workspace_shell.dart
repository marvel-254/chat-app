import 'package:flutter/material.dart';

import '../screens/navigation/nav_sidebar.dart';
import '../theme/app_colors.dart' as app_colors;
import 'responsive_app_shell.dart';

/// Three-pane workspace for wide desktop windows: nav rail, a fixed 320 px
/// list pane, and an expanded detail pane. Narrow windows never build this.
class DesktopWorkspaceShell extends StatelessWidget {
  const DesktopWorkspaceShell({
    super.key,
    required this.navIndex,
    required this.listPane,
    required this.detailPane,
    this.listTitle,
    this.listActions = const <Widget>[],
    this.detailTitle,
    this.detailSubtitle,
    this.detailActions = const <Widget>[],
    this.showDetailHeader = true,
  });

  final int navIndex;
  final Widget listPane;
  final Widget detailPane;
  final String? listTitle;
  final List<Widget> listActions;
  final String? detailTitle;
  final String? detailSubtitle;
  final List<Widget> detailActions;
  final bool showDetailHeader;

  static const double listPaneWidth = 320;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: app_colors.bg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavSidebar(),
          SizedBox(
            width: listPaneWidth,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: app_colors.surfaceLow,
                border: Border(
                  right: BorderSide(color: app_colors.border, width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (listTitle != null)
                    WorkspaceHeader(
                      title: listTitle!,
                      subtitle: null,
                      actions: listActions,
                      horizontalPadding: 16,
                    ),
                  Expanded(child: listPane),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showDetailHeader && detailTitle != null)
                  WorkspaceHeader(
                    title: detailTitle!,
                    subtitle: detailSubtitle,
                    actions: detailActions,
                    horizontalPadding: 24,
                  ),
                Expanded(child: detailPane),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
