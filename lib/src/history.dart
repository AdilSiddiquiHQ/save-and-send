import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'native.dart';

/// One entry in the "Recent" sheet.
///
/// It points at the copy that lives in the Gallery (a MediaStore URI, or a
/// path on Android 9 and older), never at the download cache, because the cache
/// for older links is cleared on the next download.
@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.sizeBytes,
    required this.durationMs,
    required this.kind,
    this.uri,
    this.path,
    this.thumbnailPath,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final int sizeBytes;
  final int durationMs;
  final String kind;
  final String? uri;
  final String? path;
  final String? thumbnailPath;

  bool get isAudio => kind == 'audio';
  String get mime => isAudio ? 'audio/mpeg' : 'video/mp4';

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'sizeBytes': sizeBytes,
        'durationMs': durationMs,
        'kind': kind,
        if (uri != null) 'uri': uri,
        if (path != null) 'path': path,
        if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Video',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num?)?.toInt() ?? 0,
      ),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      kind: json['kind'] as String? ?? 'video',
      uri: json['uri'] as String?,
      path: json['path'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
    );
  }

  factory HistoryEntry.fromResult(VideoResult result) {
    final now = DateTime.now();
    // A split adds several entries in the same millisecond, so the timestamp
    // alone is not enough to keep them apart.
    final suffix = result.path.hashCode.abs().toRadixString(36);
    return HistoryEntry(
      id: '${now.microsecondsSinceEpoch}-$suffix',
      title: result.title,
      createdAt: now,
      sizeBytes: result.sizeBytes,
      durationMs: result.durationMs,
      kind: result.kind,
      uri: result.uri,
      path: result.savedPath,
      thumbnailPath: result.thumbnailPath,
    );
  }
}

/// Recent downloads, stored as JSON in the app's private preferences.
///
/// There is no database and nothing leaves the phone. Entries are dropped when
/// the file is deleted from the Gallery so the list never points at nothing.
class HistoryStore {
  static const _key = 'history_v1';
  static const int limit = 30;

  static Future<List<HistoryEntry>> load() async {
    try {
      final raw = await NativeBridge.getPref(_key);
      if (raw == null || raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((entry) => HistoryEntry.fromJson(entry.cast<String, dynamic>()))
          .where((entry) => entry.id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(HistoryEntry entry) async {
    final items = List<HistoryEntry>.from(await load());
    items.removeWhere((existing) => existing.id == entry.id);
    items.insert(0, entry);
    if (items.length > limit) items.removeRange(limit, items.length);
    await _save(items);
  }

  static Future<void> remove(String id) async {
    final items = List<HistoryEntry>.from(await load())
      ..removeWhere((entry) => entry.id == id);
    await _save(items);
  }

  static Future<void> clear() async {
    await NativeBridge.setPref(_key, '[]');
  }

  static Future<void> _save(List<HistoryEntry> items) {
    return NativeBridge.setPref(
      _key,
      jsonEncode(items.map((entry) => entry.toJson()).toList()),
    );
  }
}
