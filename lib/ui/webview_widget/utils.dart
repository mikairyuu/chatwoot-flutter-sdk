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
      setTimeout(sendChatwootMessages, 300);
      setTimeout(sendChatwootMessages, 1000);
      setTimeout(sendChatwootMessages, 2000);
    })();
  ''';
}

const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);
final secureStorage = new FlutterSecureStorage(aOptions: _androidOptions);
const cookieKey = 'cwCookie';

class StoreHelper {
  static Future<String> getCookie() async {
    final cookie = await secureStorage.read(key: cookieKey);
    return cookie ?? "";
  }

  static storeCookie(value) async {
    await secureStorage.write(key: cookieKey, value: value);
  }
}
