import "dart:convert";

import "package:chatwoot_sdk/data/local/entity/chatwoot_user.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";

import "constants.dart";

bool isJsonString(string) {
  try {
    jsonDecode(string);
  } catch (e) {
    return false;
  }
  return true;
}

String createWootPostMessage(Map<String, dynamic> object) {
  final payload = '$WOOT_PREFIX${jsonEncode(object)}';

  return '''
    (function () {
      try {
        window.postMessage(${jsonEncode(payload)}, '*');
      } catch (e) {
        console.error('Chatwoot postMessage failed', e);
      }
    })();
  ''';
}

Map<String, dynamic> cleanJson(Map<String, dynamic> json) {
  json.removeWhere((key, value) => value == null);
  return json;
}

String getMessage(String data) {
  return data.replaceAll(WOOT_PREFIX, '');
}

dynamic _mergeCustomAttributes(
  dynamic userAttributes,
  dynamic widgetAttributes,
) {
  if (userAttributes is Map && widgetAttributes is Map) {
    return <String, dynamic>{
      ...userAttributes.map((key, value) => MapEntry(key.toString(), value)),
      ...widgetAttributes.map((key, value) => MapEntry(key.toString(), value)),
    };
  }

  return widgetAttributes ?? userAttributes;
}

String generateScripts({
  ChatwootUser? user,
  String? locale,
  dynamic customAttributes,
}) {
  final messages = <Map<String, dynamic>>[];
  final identifiedUser =
      user != null && user.identifier != null && user.identifier!.isNotEmpty
      ? user
      : null;

  if (identifiedUser != null) {
    final mergedCustomAttributes = _mergeCustomAttributes(
      identifiedUser.customAttributes,
      customAttributes,
    );

    // Chatwoot setUser(identifier, user): identifier is top-level, while the
    // profile and custom attributes are sent inside the `user` object.
    final userJson = cleanJson({
      "email": identifiedUser.email,
      "name": identifiedUser.name,
      "phone_number": identifiedUser.phone_number,
      "avatar_url": identifiedUser.avatarUrl,
      "identifier_hash": identifiedUser.identifierHash,
      "custom_attributes": mergedCustomAttributes,
    });

    messages.add({
      "event": PostMessageEvents.SET_USER,
      "identifier": identifiedUser.identifier,
      "user": userJson,
    });
  }

  if (locale != null) {
    messages.add({"event": PostMessageEvents.SET_LOCALE, "locale": locale});
  }

  // For identified users custom attributes go through the same set-user request.
  // Sending a second request concurrently can update the old anonymous contact
  // when set-user switches the widget to another contact/auth token.
  if (identifiedUser == null && customAttributes != null) {
    messages.add({
      "event": PostMessageEvents.SET_CUSTOM_ATTRIBUTES,
      "customAttributes": customAttributes,
    });
  }

  final payloads = messages
      .map((message) => '$WOOT_PREFIX${jsonEncode(message)}')
      .toList();

  final prefix = jsonEncode(WOOT_PREFIX);

  return '''
    (function () {
      const prefix = $prefix;

      function sendToFlutter(message) {
        if (
          window.ReactNativeWebView &&
          typeof window.ReactNativeWebView.postMessage === 'function'
        ) {
          window.ReactNativeWebView.postMessage(
            prefix + JSON.stringify(message)
          );
        }
      }

      // Chatwoot sends setAuthCookie/error through window.parent.postMessage.
      // In a top-level Flutter WebView parent === window, so forward those
      // events to the JavaScriptChannel too.
      if (!window.__chatwootFlutterBridgeInstalled) {
        window.__chatwootFlutterBridgeInstalled = true;

        window.addEventListener('message', function (event) {
          try {
            const rawMessage = event.data;

            if (
              typeof rawMessage !== 'string' ||
              rawMessage.indexOf(prefix) !== 0
            ) {
              return;
            }

            const parsedMessage = JSON.parse(
              rawMessage.substring(prefix.length)
            );

            if (parsedMessage.event === 'setAuthCookie') {
              const widgetAuthToken =
                parsedMessage.data && parsedMessage.data.widgetAuthToken;

              if (widgetAuthToken) {
                sendToFlutter({
                  event: 'auth-token-updated',
                  config: {
                    authToken: widgetAuthToken
                  }
                });
              }
            } else if (parsedMessage.event === 'error') {
              sendToFlutter({
                event: 'chatwoot-error',
                errorType: parsedMessage.errorType,
                data: parsedMessage.data
              });
            }
          } catch (error) {
            console.error(
              'Chatwoot Flutter message bridge failed',
              error
            );
          }
        });
      }

      const messages = ${jsonEncode(payloads)};

      // De-duplicate only in this document. After an auth-token navigation the
      // page has a fresh JS context and must receive identity/configuration again.
      if (!window.__chatwootFlutterConfigurationApplied) {
        window.__chatwootFlutterConfigurationApplied = true;

        messages.forEach(function (message) {
          try {
            window.postMessage(message, '*');
          } catch (error) {
            console.error('Chatwoot postMessage failed', error);
          }
        });
      }

    })();
  ''';
}

const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
final secureStorage = new FlutterSecureStorage(aOptions: _androidOptions);

const legacyCookieKey = 'cwCookie';

class StoreHelper {
  static String _scopedCookieKey({
    required String baseUrl,
    required String websiteToken,
    String? userIdentifier,
  }) {
    final normalizedBaseUrl = baseUrl.replaceAll(RegExp(r'/$'), '');
    final userKey = userIdentifier != null && userIdentifier.isNotEmpty
        ? userIdentifier
        : 'anonymous';

    return 'cwCookie:'
        '${Uri.encodeComponent(normalizedBaseUrl)}:'
        '${Uri.encodeComponent(websiteToken)}:'
        '${Uri.encodeComponent(userKey)}';
  }

  static Future<String> getCookie({
    required String baseUrl,
    required String websiteToken,
    String? userIdentifier,
  }) async {
    final cookie = await secureStorage.read(
      key: _scopedCookieKey(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        userIdentifier: userIdentifier,
      ),
    );

    return cookie ?? "";
  }

  static Future<void> storeCookie(
    String value, {
    required String baseUrl,
    required String websiteToken,
    String? userIdentifier,
  }) async {
    await secureStorage.write(
      key: _scopedCookieKey(
        baseUrl: baseUrl,
        websiteToken: websiteToken,
        userIdentifier: userIdentifier,
      ),
      value: value,
    );
  }

  static Future<void> deleteLegacyCookie() async {
    await secureStorage.delete(key: legacyCookieKey);
  }
}
