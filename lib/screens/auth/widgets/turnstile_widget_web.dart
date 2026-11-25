import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Cloudflare Turnstile site key injected at build time via `--dart-define`.
const String turnstileSiteKey = String.fromEnvironment('TURNSTILE_SITE_KEY');

/// Renders a Cloudflare Turnstile widget on Flutter Web when
/// `TURNSTILE_SITE_KEY` is configured.
class TurnstileWidget extends StatefulWidget {
  const TurnstileWidget({
    super.key,
    required this.onToken,
  });

  final ValueChanged<String?> onToken;

  @override
  State<TurnstileWidget> createState() => _TurnstileWidgetState();
}

class _TurnstileWidgetState extends State<TurnstileWidget> {
  static int _nextViewId = 0;
  late final String _viewType = 'bro-turnstile-${_nextViewId++}';
  String? _widgetId;

  @override
  void initState() {
    super.initState();
    if (turnstileSiteKey.isEmpty) return;

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final document = globalContext['document'] as JSObject;
      final container = document.callMethod<JSObject>(
        'createElement'.toJS,
        'div'.toJS,
      );
      container['id'] = _viewType.toJS;
      final style = container['style'] as JSObject;
      style['width'] = '100%'.toJS;
      style['minHeight'] = '65px'.toJS;
      _ensureScriptAndRender(container);
      return container;
    });
  }

  void _ensureScriptAndRender(JSObject container) {
    final turnstile = globalContext['turnstile'];
    if (turnstile.isUndefinedOrNull) {
      final document = globalContext['document'] as JSObject;
      final existing = document.callMethod<JSAny?>(
        'querySelector'.toJS,
        'script[data-bro-turnstile="true"]'.toJS,
      );
      if (existing.isUndefinedOrNull) {
        final script = document.callMethod<JSObject>(
          'createElement'.toJS,
          'script'.toJS,
        );
        script['src'] =
            'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit'
                .toJS;
        script['async'] = true.toJS;
        script['defer'] = true.toJS;
        script.callMethod<JSAny?>(
          'setAttribute'.toJS,
          'data-bro-turnstile'.toJS,
          'true'.toJS,
        );
        script.callMethod<JSAny?>(
          'addEventListener'.toJS,
          'load'.toJS,
          ((JSAny _) {
            _renderTurnstile(container);
          }).toJS,
        );
        final head = document['head'] as JSObject?;
        head?.callMethod<JSAny?>('append'.toJS, script);
      } else {
        (existing as JSObject).callMethod<JSAny?>(
          'addEventListener'.toJS,
          'load'.toJS,
          ((JSAny _) {
            _renderTurnstile(container);
          }).toJS,
        );
      }
      return;
    }
    _renderTurnstile(container);
  }

  void _renderTurnstile(JSObject container) {
    final turnstile = globalContext['turnstile'];
    if (turnstile.isUndefinedOrNull) return;
    final options = JSObject();
    options['sitekey'] = turnstileSiteKey.toJS;
    options['theme'] = 'dark'.toJS;
    options['callback'] = ((JSString token) {
      if (mounted) widget.onToken(token.toDart);
    }).toJS;
    options['expired-callback'] = (() {
      if (mounted) widget.onToken(null);
    }).toJS;
    options['error-callback'] = (() {
      if (mounted) widget.onToken(null);
    }).toJS;

    final result = (turnstile as JSObject).callMethod<JSAny?>(
      'render'.toJS,
      container,
      options,
    );
    _widgetId = result?.dartify()?.toString();
  }

  @override
  void dispose() {
    final id = _widgetId;
    if (id != null) {
      final turnstile = globalContext['turnstile'];
      if (!turnstile.isUndefinedOrNull) {
        try {
          (turnstile as JSObject).callMethod<JSAny?>('remove'.toJS, id.toJS);
        } catch (_) {}
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (turnstileSiteKey.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SizedBox(
        height: 68,
        child: HtmlElementView(viewType: _viewType),
      ),
    );
  }
}
