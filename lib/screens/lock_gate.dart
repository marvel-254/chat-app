import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_lock.dart';

class _C {
  static const bg = Color(0xFF121318);
  static const surface = Color(0xFF1E1F25);
  static const text = Color(0xFFE3E1E9);
  static const muted = Color(0xFFC5C9AC);
  static const primary = Color(0xFFD4FF00);
  static const darkOnAccent = Color(0xFF0C0D12);
}

/// Full-screen lock: biometrics, then a PIN pad.
class LockGate extends StatefulWidget {
  const LockGate({
    super.key,
    required this.title,
    required this.reason,
    required this.onUnlocked,
    this.allowSkip = false,
  });

  final String title;
  final String reason;
  final VoidCallback onUnlocked;
  final bool allowSkip;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _hasPin = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final hasPin = await AppLock.hasPin();
    if (mounted) setState(() => _hasPin = hasPin);
    final ok = await AppLock.authenticate(reason: widget.reason);
    if (ok && mounted) widget.onUnlocked();
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submitPin() async {
    final value = _pin.text.trim();
    if (value.length < 4) {
      setState(() => _error = 'Use at least 4 digits.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = _hasPin
        ? await AppLock.verifyPin(value)
        : true;
    if (!_hasPin && ok) await AppLock.setPin(value);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() => _error = "That PIN doesn't match.");
      _pin.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              const Icon(Icons.lock_outline_rounded,
                  size: 72, color: _C.primary),
              const SizedBox(height: 20),
              Text(widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _C.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                _hasPin
                    ? 'Use biometrics or your BRO PIN'
                    : 'Set a 4+ digit PIN so you can unlock without biometrics',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _C.muted, fontSize: 15),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                    color: _C.text, fontSize: 22, letterSpacing: 8),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'PIN',
                  hintStyle: const TextStyle(color: _C.muted, letterSpacing: 2),
                  filled: true,
                  fillColor: _C.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _submitPin(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _submitPin,
                style: FilledButton.styleFrom(
                  backgroundColor: _C.primary,
                  foregroundColor: _C.darkOnAccent,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(_hasPin ? 'Unlock' : 'Set PIN and unlock',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final ok = await AppLock.authenticate(
                            reason: widget.reason);
                        if (ok && mounted) widget.onUnlocked();
                      },
                icon: const Icon(Icons.fingerprint),
                label: const Text('Try biometrics'),
              ),
              if (widget.allowSkip)
                TextButton(
                  onPressed: widget.onUnlocked,
                  child: const Text('Not now'),
                ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two-step PIN setup used when turning app lock on.
Future<bool> promptSetPin(BuildContext context) async {
  final first = TextEditingController();
  final second = TextEditingController();
  try {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Set a PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('You will need this if biometrics are unavailable.'),
            const SizedBox(height: 12),
            TextField(
              controller: first,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'PIN'),
            ),
            TextField(
              controller: second,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Confirm PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (first.text.trim().length < 4) return;
              if (first.text.trim() != second.text.trim()) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AppLock.setPin(first.text.trim());
      return true;
    }
    return false;
  } finally {
    first.dispose();
    second.dispose();
  }
}
