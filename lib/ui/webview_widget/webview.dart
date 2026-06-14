import 'dart:convert';
import 'dart:io';

import 'package:chatwoot_sdk/chatwoot_sdk.dart';
import 'package:chatwoot_sdk/ui/webview_widget/utils.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart'
    as webview_flutter_android;
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart'
    as webview_flutter_wkwebview;

///Chatwoot webview widget
/// {@category FlutterClientSdk}
class Webview extends StatefulWidget {
  final String baseUrl;
  final String websiteToken;
  final String? userIdentifier;

  /// Url for Chatwoot widget in webview
  late final String widgetUrl;

  /// Chatwoot user & locale initialisation script
  late final String injectedJavaScript;

  /// See [ChatwootWidget.closeWidget]
  final void Function()? closeWidget;

  /// See [ChatwootWidget.onAttachFile]
  final Future<List<String>> Function()? onAttachFile;

  /// See [ChatwootWidget.onLoadStarted]
  final void Function()? onLoadStarted;

  /// See [ChatwootWidget.onLoadProgress]
  final void Function(int)? onLoadProgress;

  /// See [ChatwootWidget.onLoadCompleted]
  final void Function()? onLoadCompleted;

  Webview({
    Key? key,
    required this.websiteToken,
    required this.baseUrl,
    ChatwootUser? user,
    String locale = "en",
    customAttributes,
    this.closeWidget,
    this.onAttachFile,
    this.onLoadStarted,
    this.onLoadProgress,
    this.onLoadCompleted,
  })  : userIdentifier = user?.identifier,
        super(key: key) {
    widgetUrl =
        "$baseUrl/widget?website_token=$websiteToken&locale=$locale";

    injectedJavaScript = generateScripts(
      user: user,
      locale: locale,
      customAttributes: customAttributes,
    );
  }

  @override
  _WebviewState createState() => _WebviewState();
}

class _WebviewState extends State<Webview> {
  WebViewController? _controller;
  late final WebViewController controller;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      String webviewUrl = widget.widgetUrl;

      // Old SDK versions stored one global cwCookie.
      // On iOS Keychain it may survive reinstall and poison the widget session.
      try {
        await StoreHelper.deleteLegacyCookie();
      } catch (e, st) {
        debugPrint('Chatwoot legacy cookie delete failed: $e\n$st');
      }

      final cwCookie = await StoreHelper.getCookie(
        baseUrl: widget.baseUrl,
        websiteToken: widget.websiteToken,
        userIdentifier: widget.userIdentifier,
      );

      if (!mounted) return;

      if (cwCookie.isNotEmpty) {
        webviewUrl = "$webviewUrl&cw_conversation=$cwCookie";
      }

      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              widget.onLoadProgress?.call(progress);
            },
            onPageStarted: (String url) {
              widget.onLoadStarted?.call();
            },
            onPageFinished: (String url) async {
              widget.onLoadCompleted?.call();
            },
            onWebResourceError: (WebResourceError error) {
              debugPrint(
                'Chatwoot WebResourceError: '
                'code=${error.errorCode}, '
                'type=${error.errorType}, '
                'description=${error.description}, '
                'url=${error.url}, '
                'isForMainFrame=${error.isForMainFrame}',
              );
            },
            onNavigationRequest: (NavigationRequest request) {
              final uri = Uri.tryParse(request.url);

              if (uri == null) {
                return NavigationDecision.prevent;
              }

              if (uri.scheme == 'about' ||
                  uri.scheme == 'data' ||
                  uri.scheme == 'blob') {
                return NavigationDecision.navigate;
              }

              final baseUri = Uri.parse(widget.baseUrl);

              final isChatwootUrl =
                  uri.scheme == baseUri.scheme && uri.host == baseUri.host;

              if (isChatwootUrl) {
                return NavigationDecision.navigate;
              }

              launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            },
          ),
        )
        ..addJavaScriptChannel(
          "ReactNativeWebView",
          onMessageReceived: (JavaScriptMessage jsMessage) async {
            debugPrint("Chatwoot message received: ${jsMessage.message}");

            final message = getMessage(jsMessage.message);

            if (isJsonString(message)) {
              final parsedMessage = jsonDecode(message);
              final eventType = parsedMessage["event"];
              final type = parsedMessage["type"];

              if (eventType == 'loaded') {
                final authToken = parsedMessage["config"]?["authToken"];

                if (authToken is String && authToken.isNotEmpty) {
                  try {
                    await StoreHelper.storeCookie(
                      authToken,
                      baseUrl: widget.baseUrl,
                      websiteToken: widget.websiteToken,
                      userIdentifier: widget.userIdentifier,
                    );
                  } catch (e, st) {
                    debugPrint('Chatwoot cookie save failed: $e\n$st');
                  }
                }

                await controller.runJavaScript(widget.injectedJavaScript);
              }

              if (type == 'close-widget') {
                if (widget.closeWidget != null) {
                  widget.closeWidget!.call();
                } else if (mounted) {
                  Navigator.of(context).maybePop();
                }
              }
            }
          },
        );

      if (Platform.isIOS &&
          controller.platform
              is webview_flutter_wkwebview.WebKitWebViewController) {
        final iosController =
            controller.platform
                as webview_flutter_wkwebview.WebKitWebViewController;

        iosController.setAllowsBackForwardNavigationGestures(false);
      }

      if (Platform.isAndroid && widget.onAttachFile != null) {
        final androidController =
            controller.platform
                as webview_flutter_android.AndroidWebViewController;

        androidController.setOnShowFileSelector(
          (_) => widget.onAttachFile!.call(),
        );
      }

      if (!mounted) return;

      setState(() {
        _controller = controller;
      });

      await controller.loadRequest(Uri.parse(webviewUrl));
    });
  }

  @override
  Widget build(BuildContext context) {
    return _controller != null
        ? WebViewWidget(controller: _controller!)
        : SizedBox();
  }
}
