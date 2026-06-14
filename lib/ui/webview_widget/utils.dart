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

String generateScripts({
  ChatwootUser? user,
  String? locale,
  dynamic customAttributes,
}) {
  final messages = <Map<String, dynamic>>[];

  if (user != null && user.identifier != null && user.identifier!.isNotEmpty) {
    final userJson = cleanJson(Map<String, dynamic>.from(user.toJson()));

    messages.add({
      "event": PostMessageEvents.SET_USER,
      "identifier": user.identifier,
      "user": userJson,
    });
  }

  if (locale != null) {
    messages.add({"event": PostMessageEvents.SET_LOCALE, "locale": locale});
  }

  if (customAttributes != null) {
    messages.add({
      "event": PostMessageEvents.SET_CUSTOM_ATTRIBUTES,
      "customAttributes": customAttributes,
    });
  }

  final payloads = messages.map((m) => '$WOOT_PREFIX${jsonEncode(m)}').toList();

  return '''
    (function () {
      const messages = ${jsonEncode(payloads)};

      function sendChatwootMessages() {
        messages.forEach(function (message) {
          try {
            window.postMessage(message, '*');
          } catch (e) {
            console.error('Chatwoot postMessage failed', e);
          }
        });
      }

      sendChatwootMessages();
      setTimeout(sendChatwootMessages, 500);
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
    final userKey =
        userIdentifier != null && userIdentifier.isNotEmpty
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
