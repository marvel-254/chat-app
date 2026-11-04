import 'package:flutter/material.dart';

import '../services/update_logic.dart';
import '../services/update_service.dart';
import '../services/apk_installer.dart';

/// The stage the update dialog is currently showing.
enum _Phase {
  /// The "update available / update required" prompt.
  prompt,

  /// Downloading the APK with a live progress bar.
  downloading,

  /// A download/install failure with a Retry action.
  failed,

  /// Explains the Android install-permission step before handoff.
  explaining,

  /// Handed off to the system installer; Android keeps control.
  installing,
}

/// Opens the non-dismissible update flow dialog and drives it to completion.
///
/// [onDownload] runs the download (reporting 0..1 progress) and returns when
/// the APK has been verified and written to disk. [onInstall] hands the file
/// to the system installer. Both throw [UpdateException] on failure. For a
/// [UpdatePriority.mandatory] release the "Later" action is hidden.
Future<void> showUpdateFlow(
  BuildContext context, {
  required ReleaseInfo release,
  required ApkAsset asset,
  required UpdatePriority priority,
  required Future<void> Function(void Function(double) onProgress) onDownload,
  required Future<void> Function() onInstall,
  Future<void> Function()? onPostpone,
  required ApkInstaller installer,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdateFlowDialog(
      release: release,
      asset: asset,
      priority: priority,
      onDownload: onDownload,
      onInstall: onInstall,
      onPostpone: onPostpone,
      installer: installer,
    ),
  );
}

/// One dialog that walks the whole update flow. Kept as a single non-dismissible
/// modal so an interrupted handoff can never leave the app half-updated.
class UpdateFlowDialog extends StatefulWidget {
  const UpdateFlowDialog({
    super.key,
    required this.release,
    required this.asset,
    required this.priority,
    required this.onDownload,
    required this.onInstall,
    this.onPostpone,
    required this.installer,
  });

  final ReleaseInfo release;
  final ApkAsset asset;

  /// Whether the release is optional or mandatory (mandatory hides "Later").
  final UpdatePriority priority;

  /// Runs the download, reporting progress 0..1. Throws [UpdateException].
  final Future<void> Function(void Function(double) onProgress) onDownload;

  /// Hands the downloaded APK to the system installer. Throws
  /// [UpdateException].
  final Future<void> Function() onInstall;

  /// Persists "remind me later" for this release (optional updates only).
  final Future<void> Function()? onPostpone;

  final ApkInstaller installer;

  @override
  State<UpdateFlowDialog> createState() => _UpdateFlowDialogState();
}

class _UpdateFlowDialogState extends State<UpdateFlowDialog> {
  _Phase _phase = _Phase.prompt;
  double _progress = 0;
  String? _failureMessage;

  bool get _mandatory => widget.priority == UpdatePriority.mandatory;

  Future<void> _startDownload() async {
    setState(() {
      _phase = _Phase.downloading;
      _failureMessage = null;
      _progress = 0;
    });
    try {
      await widget.onDownload((p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      setState(() => _phase = _Phase.explaining);
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _failureMessage = _messageFor(e.kind);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _failureMessage = _messageFor('network');
      });
    }
  }

  Future<void> _install() async {
    setState(() {
      _phase = _Phase.installing;
      _failureMessage = null;
    });
    try {
      // On success the system installer takes over and the app goes to the
      // background; the dialog stays until the version refresh on resume.
      await widget.onInstall();
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _failureMessage = _messageFor(e.kind);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _failureMessage = _messageFor('install');
      });
    }
  }

  Future<void> _later() async {
    try {
      await widget.onPostpone?.call();
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  String _messageFor(String kind) => switch (kind) {
        'checksum' =>
          'The downloaded file did not pass its integrity check. Download it again.',
        'storage' => 'There isn’t enough free space for the update. Free up some '
            'space, then try again.',
        'installRejected' => 'Android declined the install request. Try again — '
            'if it keeps failing, open Settings → Install unknown apps and '
            'allow BRO, then retry.',
        'install' => 'This device can’t install APK files right now.',
        'malformed' => 'The downloaded file isn’t a valid app. Download it again.',
        _ => 'Could not reach the update server. Check your connection and retry.',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      icon: Icon(_phaseIcon(scheme)),
      title: Text(_phaseTitle(scheme)),
      content: _phaseBody(scheme),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: _phaseActions(scheme),
    );
  }

  // --- phase rendering ----------------------------------------------------

  IconData _phaseIcon(ColorScheme scheme) => switch (_phase) {
        _Phase.prompt => Icons.system_update_alt,
        _Phase.downloading => Icons.downloading,
        _Phase.failed => Icons.error_outline,
        _Phase.explaining => Icons.security_outlined,
        _Phase.installing => Icons.android,
      };

  String _phaseTitle(ColorScheme scheme) => switch (_phase) {
        _Phase.prompt => _mandatory ? 'Update required' : 'Update available',
        _Phase.downloading => 'Downloading update…',
        _Phase.failed => 'Update failed',
        _Phase.explaining => 'Ready to install',
        _Phase.installing => 'Installing…',
      };

  Widget _phaseBody(ColorScheme scheme) {
    final muted = scheme.onSurface.withValues(alpha: 0.66);
    switch (_phase) {
      case _Phase.prompt:
        final name = widget.release.versionName.isEmpty
            ? widget.release.tag
            : widget.release.versionName;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _mandatory
                  ? 'A newer version of BRO is here and this one expires. '
                      'Install it to keep using the app.'
                  : 'A newer version of BRO is available.',
              style: TextStyle(color: muted, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            _InfoRow(
              label: 'Version',
              value: name,
              scheme: scheme,
            ),
            const SizedBox(height: 8),
            _InfoRow(
              label: 'Size',
              value: widget.asset.sizeLabel,
              scheme: scheme,
            ),
            const SizedBox(height: 16),
            _releaseNotes(muted),
          ],
        );
      case _Phase.downloading:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Downloading ${_pct()}',
              style: TextStyle(color: muted, fontSize: 14),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.asset.sizeLabel} · this can take a minute',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        );
      case _Phase.failed:
        return Text(
          _failureMessage ?? 'Something went wrong. Try again.',
          style: TextStyle(color: muted, fontSize: 14, height: 1.4),
        );
      case _Phase.explaining:
        return Text(
          'BRO has downloaded the update and is about to install it. '
          'Android will ask for your permission and shows its own install '
          'screen — confirm it there. If you see “Install unknown apps”, '
          'allow it for BRO and confirm.',
          style: TextStyle(color: muted, fontSize: 14, height: 1.4),
        );
      case _Phase.installing:
        return Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Android is finishing the install. When it’s done, BRO will '
                'open on the new version.',
                style: TextStyle(color: muted, fontSize: 14, height: 1.4),
              ),
            ),
          ],
        );
    }
  }

  String _pct() => '${(_progress * 100).round()}%';

  Widget _releaseNotes(Color muted) {
    final notes = widget.release.notes.trim();
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 160),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: muted.withValues(alpha: 0.25),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WHAT’S NEW',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.08,
                color: muted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              notes.isEmpty ? 'No release notes for this version.' : notes,
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _phaseActions(ColorScheme scheme) {
    switch (_phase) {
      case _Phase.prompt:
        if (_mandatory) {
          return [
            FilledButton.icon(
              onPressed: _startDownload,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Update now'),
            ),
          ];
        }
        return [
          TextButton(
            onPressed: _later,
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Update now'),
          ),
        ];
      case _Phase.downloading:
      case _Phase.installing:
        return const [];
      case _Phase.failed:
        return [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(), // mandatory re-prompts later
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ];
      case _Phase.explaining:
        return [
          TextButton(
            onPressed: () async {
              if (await widget.installer.canRequestPackageInstalls()) {
                await _install();
              } else {
                await widget.installer.openInstallSettings();
              }
            },
            child: const Text('Settings'),
          ),
          FilledButton.icon(
            onPressed: _install,
            icon: const Icon(Icons.install_mobile, size: 18),
            label: const Text('Install'),
          ),
        ];
    }
  }

  Future<void> _retry() async {
    // Retry re-runs the download; an install failure simply re-tries the
    // download too (the file is still on disk and verified).
    await _startDownload();
  }
}

/// A labelled key/value row used on the update-available prompt.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.scheme,
  });

  final String label;
  final String value;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.06,
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
