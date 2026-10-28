import 'package:flutter/services.dart';

import 'models.dart';

/// The thin bridge to the Kotlin side.
class NativeBridge {
  static const MethodChannel _methods =
      MethodChannel('com.personal.save_and_send/native');
  static const EventChannel _events =
      EventChannel('com.personal.save_and_send/events');

  static Stream<DownloadEvent> get events {
    return _events.receiveBroadcastStream().map((event) {
      return DownloadEvent.fromMap(event as Map<dynamic, dynamic>);
    });
  }

  static Future<Map<String, dynamic>?> getInitialShare() async {
    return _methods.invokeMapMethod<String, dynamic>('getInitialShare');
  }

  static Future<Map<String, dynamic>> ensureEngine() async {
    final result =
        await _methods.invokeMapMethod<String, dynamic>('ensureEngine');
    return result ?? <String, dynamic>{};
  }

  static Future<void> download({
    required String url,
    required String requestId,
  }) {
    return _methods.invokeMethod<void>('download', {
      'url': url,
      'requestId': requestId,
    });
  }

  static Future<void> cancel() {
    return _methods.invokeMethod<void>('cancel');
  }

  static Future<String> shareWhatsApp(String path) async {
    return await _methods.invokeMethod<String>('shareWhatsApp', {
          'path': path,
        }) ??
        'failed';
  }

  static Future<String> shareStatus(String path) async {
    return await _methods.invokeMethod<String>('shareStatus', {
          'path': path,
        }) ??
        'failed';
  }

  static Future<String> shareSystem(String path) async {
    return await _methods.invokeMethod<String>('shareSystem', {
          'path': path,
        }) ??
        'failed';
  }

  static Future<String> shareText(String text) async {
    return await _methods.invokeMethod<String>('shareText', {
          'text': text,
        }) ??
        'failed';
  }

  static Future<bool> saveToGallery(String path) async {
    return await _methods.invokeMethod<bool>('saveToGallery', {
          'path': path,
        }) ??
        false;
  }

  static Future<void> closeApp() {
    return _methods.invokeMethod<void>('closeApp');
  }

  static Future<void> setScreenOn(bool on) {
    return _methods.invokeMethod<void>('setScreenOn', {'on': on});
  }

  static Future<String?> engineVersion() {
    return _methods.invokeMethod<String>('engineVersion');
  }

  static Future<Map<String, dynamic>> updateEngine() async {
    final result =
        await _methods.invokeMapMethod<String, dynamic>('updateEngine');
    return result ?? <String, dynamic>{};
  }

  static Future<bool> hasCookies() async {
    return await _methods.invokeMethod<bool>('hasCookies') ?? false;
  }

  static Future<bool> setCookies(String? text) async {
    return await _methods.invokeMethod<bool>('setCookies', {
          'text': text,
        }) ??
        false;
  }

  static Future<String?> getPref(String key) {
    return _methods.invokeMethod<String>('getPref', {'key': key});
  }

  static Future<void> setPref(String key, String value) {
    return _methods.invokeMethod<void>('setPref', {
      'key': key,
      'value': value,
    });
  }
}
