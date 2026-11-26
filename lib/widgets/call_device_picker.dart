import 'package:flutter/material.dart';

enum CallDeviceKind { microphone, speaker, camera }

/// Bottom sheet used during a call to pick a capture/output device.
/// Device IDs come from MediaDevices and the caller owns the switch.
Future<void> showCallDevicePicker({
  required BuildContext context,
  required Map<CallDeviceKind, List<CallDeviceEntry>> devices,
  required ValueChanged<CallDeviceEntry> onSelected,
  String? currentMicrophoneId,
  String? currentSpeakerId,
  String? currentCameraId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1B1C22),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      final kinds = <CallDeviceKind>[
        CallDeviceKind.microphone,
        CallDeviceKind.speaker,
        CallDeviceKind.camera,
      ].where((kind) => (devices[kind] ?? const []).isNotEmpty).toList();
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Call devices',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (kinds.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    'No extra devices found. Connect a headset or camera and try again.',
                    style: TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final kind in kinds) ...[
                        _DeviceSectionLabel(label: _labelFor(kind)),
                        for (final entry in devices[kind]!) ListTile(
                          leading: Icon(
                            _iconFor(kind),
                            color: entry.isSelected ? const Color(0xFF6D8BFF) : Colors.white54,
                          ),
                          title: Text(
                            entry.label.isEmpty ? 'Unnamed device' : entry.label,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: entry.isSelected
                              ? const Text(
                                  'In use',
                                  style: TextStyle(color: Color(0xFF6D8BFF)),
                                )
                              : null,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            onSelected(entry);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class CallDeviceEntry {
  const CallDeviceEntry({
    required this.id,
    required this.label,
    required this.kind,
    required this.isSelected,
  });

  final String id;
  final String label;
  final CallDeviceKind kind;
  final bool isSelected;
}

String _labelFor(CallDeviceKind kind) {
  switch (kind) {
    case CallDeviceKind.microphone:
      return 'Microphone';
    case CallDeviceKind.speaker:
      return 'Speaker';
    case CallDeviceKind.camera:
      return 'Camera';
  }
}

IconData _iconFor(CallDeviceKind kind) {
  switch (kind) {
    case CallDeviceKind.microphone:
      return Icons.mic_none_rounded;
    case CallDeviceKind.speaker:
      return Icons.volume_down_rounded;
    case CallDeviceKind.camera:
      return Icons.videocam_outlined;
  }
}

class _DeviceSectionLabel extends StatelessWidget {
  const _DeviceSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 11,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
