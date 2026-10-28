class DownloadEvent {
  const DownloadEvent({
    required this.type,
    this.requestId,
    this.percent,
    this.etaSeconds,
    this.stage,
    this.path,
    this.title,
    this.durationMs,
    this.width,
    this.height,
    this.hasAudio,
    this.thumbnailPath,
    this.thumbnailUrl,
    this.trimmed,
    this.sizeBytes,
    this.saved,
    this.message,
    this.detail,
    this.code,
    this.url,
    this.error,
  });

  final String type;
  final String? requestId;
  final double? percent;
  final int? etaSeconds;
  final String? stage;
  final String? path;
  final String? title;
  final int? durationMs;
  final int? width;
  final int? height;
  final bool? hasAudio;
  final String? thumbnailPath;
  final String? thumbnailUrl;
  final bool? trimmed;
  final int? sizeBytes;
  final bool? saved;
  final String? message;
  final String? detail;
  final String? code;
  final String? url;
  final String? error;

  factory DownloadEvent.fromMap(Map<dynamic, dynamic> map) {
    int? asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return null;
    }

    double? asDouble(dynamic value) {
      if (value is double) return value;
      if (value is num) return value.toDouble();
      return null;
    }

    bool? asBool(dynamic value) => value is bool ? value : null;
    String? asString(dynamic value) => value is String ? value : null;

    return DownloadEvent(
      type: asString(map['type']) ?? '',
      requestId: asString(map['requestId']),
      percent: asDouble(map['percent']),
      etaSeconds: asInt(map['etaSeconds']),
      stage: asString(map['stage']),
      path: asString(map['path']),
      title: asString(map['title']),
      durationMs: asInt(map['durationMs']),
      width: asInt(map['width']),
      height: asInt(map['height']),
      hasAudio: asBool(map['hasAudio']),
      thumbnailPath: asString(map['thumbnailPath']),
      thumbnailUrl: asString(map['thumbnailUrl']),
      trimmed: asBool(map['trimmed']),
      sizeBytes: asInt(map['sizeBytes']),
      saved: asBool(map['saved']),
      message: asString(map['message']),
      detail: asString(map['detail']),
      code: asString(map['code']),
      url: asString(map['url']),
      error: asString(map['error']),
    );
  }
}

class VideoResult {
  const VideoResult({
    required this.path,
    required this.title,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.hasAudio,
    required this.trimmed,
    required this.sizeBytes,
    this.thumbnailPath,
    this.thumbnailUrl,
  });

  final String path;
  final String title;
  final int durationMs;
  final int width;
  final int height;
  final bool hasAudio;
  final bool trimmed;
  final int sizeBytes;
  final String? thumbnailPath;
  final String? thumbnailUrl;

  factory VideoResult.fromEvent(DownloadEvent event) {
    return VideoResult(
      path: event.path ?? '',
      title: (event.title ?? '').trim().isEmpty ? 'Video' : event.title!.trim(),
      durationMs: event.durationMs ?? 0,
      width: event.width ?? 0,
      height: event.height ?? 0,
      hasAudio: event.hasAudio ?? false,
      trimmed: event.trimmed ?? false,
      sizeBytes: event.sizeBytes ?? 0,
      thumbnailPath: event.thumbnailPath,
      thumbnailUrl: event.thumbnailUrl,
    );
  }

  double get aspectRatio {
    if (width <= 0 || height <= 0) return 9 / 16;
    return (width / height).clamp(0.4, 2.5);
  }
}
