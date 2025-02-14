import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../constants/constants.dart';
import '../../constants/resources.dart';
import '../../utils/extension/extension.dart';
import '../../utils/logger.dart';
import '../dialog.dart';
import '../toast.dart';

enum CaptchaType {
  gCaptcha,
  hCaptcha,
}

/// return:
/// list[0] : CaptchaType
/// list[1] : String (captcha token)
Future<List<dynamic>?> showCaptchaWebViewDialog(BuildContext context) =>
    showMixinDialog<List<dynamic>>(
      context: context,
      child: const CaptchaWebViewDialog(),
    );

class CaptchaWebViewDialog extends HookWidget {
  const CaptchaWebViewDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final timer = useRef<Timer?>(null);
    final controllerRef = useRef<WebViewController?>(null);
    final captcha = useRef<CaptchaType>(CaptchaType.gCaptcha);
    useEffect(
      () => () {
        timer.value?.cancel();
      },
      [],
    );

    void loadFallback() {
      if (captcha.value == CaptchaType.gCaptcha) {
        captcha.value = CaptchaType.hCaptcha;
        _loadCaptcha(controllerRef.value!, CaptchaType.hCaptcha);
      } else {
        controllerRef.value!.loadUrl('about:blank');
        showToastFailed(
          ToastError(context.l10n.recaptchaTimeout),
        );
        Navigator.pop(context);
      }
    }

    return SizedBox(
      width: 400,
      height: 520,
      child: WebView(
        javascriptMode: JavascriptMode.unrestricted,
        onWebViewCreated: (controller) {
          controllerRef.value = controller;
          _loadCaptcha(controller, captcha.value);
        },
        onPageStarted: (url) {
          timer.value = Timer(const Duration(seconds: 15), loadFallback);
        },
        onPageFinished: (url) {
          timer.value?.cancel();
          timer.value = null;
        },
        javascriptChannels: {
          JavascriptChannel(
            name: 'MixinContextTokenCallback',
            onMessageReceived: (message) {
              timer.value?.cancel();
              timer.value = null;
              final token = message.message;
              Navigator.pop(context, [captcha.value, token]);
            },
          ),
          JavascriptChannel(
            name: 'MixinContextErrorCallback',
            onMessageReceived: (message) {
              e('on captcha error: ${message.message}');
              timer.value?.cancel();
              timer.value = null;
              loadFallback();
            },
          ),
        },
      ),
    );
  }
}

Future<void> _loadCaptcha(
  WebViewController controller,
  CaptchaType type,
) async {
  i('load captcha: $type');
  final html = await rootBundle.loadString(Resources.assetsCaptchaHtml);
  final String apiKey;
  final String src;
  switch (type) {
    case CaptchaType.gCaptcha:
      apiKey = kRecaptchaKey;
      src = 'https://www.recaptcha.net/recaptcha/api.js'
          '?onload=onGCaptchaLoad&render=explicit';
      break;
    case CaptchaType.hCaptcha:
      apiKey = hCaptchaKey;
      src = 'https://hcaptcha.com/1/api.js'
          '?onload=onHCaptchaLoad&render=explicit';
      break;
  }
  final htmlWithCaptcha =
      html.replaceAll('#src', src).replaceAll('#apiKey', apiKey);

  await controller.clearCache();
  await controller.loadHtmlString(
    htmlWithCaptcha,
    baseUrl: 'https://mixin.one',
  );
}
