import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_colors.dart' as app_colors;
import '../../models/avatar_config.dart';
import '../../services/supabase.dart';
import '../../ui/errors.dart';
import '../../ui/states.dart';
import '../../widgets/digital_avatar.dart';
import '../../widgets/responsive_app_shell.dart';

class _P {
  static const surface = app_colors.surface;
  static const border = app_colors.border;
  static const text = app_colors.text;
  static const muted = app_colors.muted;
  static const primary = app_colors.volt;
  static const darkOnAccent = app_colors.darkOnVolt;
}

/// Customiser for the 3D digital avatar (issue #74).
///
/// Everything is a local preview backed by [AvatarConfig]; nothing is written
/// to Supabase until the user taps Save.
class DigitalAvatarScreen extends StatefulWidget {
  const DigitalAvatarScreen({super.key});

  @override
  State<DigitalAvatarScreen> createState() => _DigitalAvatarScreenState();
}

class _DigitalAvatarScreenState extends State<DigitalAvatarScreen> {
  AvatarConfig _config = const AvatarConfig();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = Supa.currentUser?.id;
    if (uid == null) {
      setState(() {
        _error = 'Sign in again to edit your avatar.';
        _loading = false;
      });
      return;
    }
    try {
      final config = await Supa.getDigitalAvatarConfig(uid);
      if (!mounted) return;
      setState(() {
        _config = config;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            friendlyErrorMessage(e, fallback: "We couldn't load your avatar.");
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supa.setDigitalAvatarConfig(_config);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Avatar saved.')));
      setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyErrorMessage(
            e, fallback: "We couldn't save your avatar. Try again.");
      });
    }
  }

  void _update(AvatarConfig next) => setState(() => _config = next);

  void _randomize() {
    final rng = math.Random();
    T pick<T>(List<T> values) => values[rng.nextInt(values.length)];
    _update(_config.copyWith(
      preset: pick(AvatarConfig.presets),
      expression: pick(AvatarConfig.expressions),
      accessory: pick(AvatarConfig.accessories),
      bodyHex: pick(AvatarConfig.bodyColors),
      auraHex: pick(AvatarConfig.auraColors),
      reaction: pick(AvatarConfig.reactions),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveAppShell(
      title: '3D avatar',
      navIndex: 0,
      showBottomNavigation: false,
      leading: IconButton(
          icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      body: _loading
          ? const FormSkeleton(label: 'Loading avatar')
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Center(
                      child: DigitalAvatar(
                        config: _config,
                        size: 168,
                        onReact: () {},
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        _config.enabled
                            ? 'This is how your profile avatar looks'
                            : 'Turn on "Show on my profile" to use it',
                        style: const TextStyle(color: _P.muted, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show on my profile'),
                      subtitle: Text(
                        'Replaces your photo avatar with this one',
                        style:
                            const TextStyle(color: _P.muted, fontSize: 12),
                      ),
                      value: _config.enabled,
                      onChanged: (v) => _update(_config.copyWith(enabled: v)),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Idle animations'),
                      subtitle: Text(
                        'Bob, breathing and blinking',
                        style:
                            const TextStyle(color: _P.muted, fontSize: 12),
                      ),
                      value: _config.animationsEnabled,
                      onChanged: (v) => _update(
                          _config.copyWith(animationsEnabled: v)),
                    ),
                    const SizedBox(height: 12),
                    const _SectionLabel('Preset'),
                    _ChoiceRow(
                      values: AvatarConfig.presets,
                      selected: _config.preset,
                      onChanged: (v) => _update(_config.copyWith(preset: v)),
                    ),
                    const SizedBox(height: 16),
                    const _SectionLabel('Expression'),
                    _ChoiceRow(
                      values: AvatarConfig.expressions,
                      selected: _config.expression,
                      onChanged: (v) =>
                          _update(_config.copyWith(expression: v)),
                    ),
                    const SizedBox(height: 16),
                    const _SectionLabel('Accessory'),
                    _ChoiceRow(
                      values: AvatarConfig.accessories,
                      selected: _config.accessory,
                      onChanged: (v) =>
                          _update(_config.copyWith(accessory: v)),
                    ),
                    const SizedBox(height: 16),
                    const _SectionLabel('Body colour'),
                    _SwatchRow(
                      values: AvatarConfig.bodyColors,
                      selected: _config.bodyHex,
                      onChanged: (v) => _update(_config.copyWith(bodyHex: v)),
                    ),
                    const SizedBox(height: 16),
                    const _SectionLabel('Aura'),
                    _SwatchRow(
                      values: AvatarConfig.auraColors,
                      selected: _config.auraHex,
                      onChanged: (v) => _update(_config.copyWith(auraHex: v)),
                    ),
                    const SizedBox(height: 16),
                    const _SectionLabel('Tap reaction'),
                    _ChoiceRow(
                      values: AvatarConfig.reactions,
                      selected: _config.reaction,
                      style: const TextStyle(fontSize: 20),
                      onChanged: (v) =>
                          _update(_config.copyWith(reaction: v)),
                    ),
                    const SizedBox(height: 24),
                    if (_error != null) ...[
                      Text(_error!,
                          style: const TextStyle(
                              color: Color(0xFFFF6B6B), fontSize: 13)),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving ? null : _randomize,
                            icon: const Icon(Icons.casino_outlined, size: 18),
                            label: const Text('Surprise me'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _P.text,
                              side: const BorderSide(color: _P.border),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const BroSpinner(
                                    size: 16, color: _P.darkOnAccent)
                                : const Icon(Icons.check, size: 18),
                            label: const Text('Save avatar'),
                            style: FilledButton.styleFrom(
                              backgroundColor: _P.primary,
                              foregroundColor: _P.darkOnAccent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: _P.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
      );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.values,
    required this.selected,
    required this.onChanged,
    this.style,
  });

  final List<String> values;
  final String selected;
  final ValueChanged<String> onChanged;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          ChoiceChip(
            label: Text(value, style: style),
            selected: value == selected,
            onSelected: (_) => onChanged(value),
            labelStyle: TextStyle(
              color: value == selected ? _P.darkOnAccent : _P.text,
              fontWeight: FontWeight.w600,
            ),
            selectedColor: _P.primary,
            backgroundColor: _P.surface,
            side: const BorderSide(color: _P.border),
            showCheckmark: false,
          ),
      ],
    );
  }
}

class _SwatchRow extends StatelessWidget {
  const _SwatchRow({
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  final List<String> values;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final value in values)
          GestureDetector(
            onTap: () => onChanged(value),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _hexColor(value),
                shape: BoxShape.circle,
                border: Border.all(
                  color: value == selected
                      ? _P.primary
                      : _P.border.withValues(alpha: 0.6),
                  width: value == selected ? 3 : 1,
                ),
              ),
            ),
          ),
      ],
    );
  }

  static Color _hexColor(String value) {
    final parsed = int.tryParse('FF${value.substring(1)}', radix: 16);
    return parsed == null ? _P.primary : Color(parsed);
  }
}
