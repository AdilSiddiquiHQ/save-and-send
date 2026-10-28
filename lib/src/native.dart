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
    int maxHeight = 0,
    bool audioOnly = false,
    bool alternate = false,
  }) {
    return _methods.invokeMethod<void>('download', {
      'url': url,
      'requestId': requestId,
      'options': {
        'maxHeight': maxHeight,
        'audioOnly': audioOnly,
        'alternate': alternate,
      },
    });
  }

  static Future<void> transform({
    required String requestId,
    required String path,
    required String title,
    required String mode,
    int startMs = 0,
    int endMs = 0,
    int targetBytes = 0,
  }) {
    return _methods.invokeMethod<void>('transform', {
      'requestId': requestId,
      'path': path,
      'title': title,
      'mode': mode,
      'startMs': startMs,
      'endMs': endMs,
      'targetBytes': targetBytes,
    });
  }

  /// A JPEG frame from [path] at [timeMs], used by the trim preview.
  static Future<String?> frameAt({
    required String path,
    required int timeMs,
  }) {
    return _methods.invokeMethod<String>('frameAt', {
      'path': path,
      'timeMs': timeMs,
    });
  }

  /// Bytes held by downloads, Status copies, and preview frames.
  static Future<int> tempSize() async {
    return await _methods.invokeMethod<int>('tempSize') ?? 0;
  }

  /// Deletes the cache folders and returns the bytes freed.
  static Future<int> clearTemp() async {
    return await _methods.invokeMethod<int>('clearTemp') ?? 0;
  }

  static Future<LinkProbe?> probe(String url) async {
    final result = await _methods.invokeMapMethod<String, dynamic>(
      'probe',
      {'url': url},
    );
    return result == null ? null : LinkProbe.fromMap(result);
  }

  static Future<String> diagnose(String url) async {
    return await _methods.invokeMethod<String>('diagnose', {'url': url}) ?? '';
  }

  static Future<bool> isOnWifi() async {
    return await _methods.invokeMethod<bool>('isOnWifi') ?? false;
  }

  static Future<String> shareWhatsAppUri(String uri, String mime) async {
    return await _methods.invokeMethod<String>('shareWhatsAppUri', {
          'uri': uri,
          'mime': mime,
        }) ??
        'failed';
  }

  static Future<String> shareStatusUri(String uri, String mime) async {
    return await _methods.invokeMethod<String>('shareStatusUri', {
          'uri': uri,
          'mime': mime,
        }) ??
        'failed';
  }

  static Future<String> shareSystemUri(String uri, String mime) async {
    return await _methods.invokeMethod<String>('shareSystemUri', {
          'uri': uri,
          'mime': mime,
        }) ??
        'failed';
  }

  static Future<bool> openUri(String uri, String mime) async {
    return await _methods.invokeMethod<bool>('openUri', {
          'uri': uri,
          'mime': mime,
        }) ??
        false;
  }

  static Future<bool> deleteUri({String? uri, String? path}) async {
    return await _methods.invokeMethod<bool>('deleteUri', {
          'uri': uri,
          'path': path,
        }) ??
        false;
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
