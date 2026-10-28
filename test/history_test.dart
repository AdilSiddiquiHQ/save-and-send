import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:save_and_send/src/history.dart';
import 'package:save_and_send/src/models.dart';

const _methodChannelName = 'com.personal.save_and_send/native';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final prefs = <String, String>{};

  setUp(() {
    prefs.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel(_methodChannelName),
      (call) async {
        final key = call.arguments['key'] as String?;
        switch (call.method) {
          case 'getPref':
            return key == null ? null : prefs[key];
          case 'setPref':
            if (key != null) {
              final value = call.arguments['value'] as String?;
              if (value == null) {
                prefs.remove(key);
              } else {
                prefs[key] = value;
              }
            }
            return null;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(_methodChannelName),
      null,
    );
  });

  HistoryEntry entry(int index) {
    return HistoryEntry(
      id: 'id-$index',
      title: 'Clip $index',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000 + index),
      sizeBytes: 1024 * index,
      durationMs: 1000 * index,
      kind: index.isEven ? 'video' : 'audio',
      uri: 'content://media/external/video/media/$index',
      thumbnailPath: '/tmp/thumb_$index.jpg',
    );
  }

  test('entry survives a JSON round trip', () {
    final original = entry(7);
    final copy = HistoryEntry.fromJson(original.toJson());

    expect(copy.id, original.id);
    expect(copy.title, original.title);
    expect(copy.createdAt, original.createdAt);
    expect(copy.sizeBytes, original.sizeBytes);
    expect(copy.durationMs, original.durationMs);
    expect(copy.kind, 'audio');
    expect(copy.isAudio, isTrue);
    expect(copy.mime, 'audio/mpeg');
    expect(copy.uri, original.uri);
    expect(copy.thumbnailPath, original.thumbnailPath);
  });

  test('newest entry comes first and the list stops at 30', () async {
    for (var index = 0; index < 35; index++) {
      await HistoryStore.add(entry(index));
    }

    final items = await HistoryStore.load();
    expect(items, hasLength(HistoryStore.limit));
    expect(items.first.id, 'id-34');
    expect(items.last.id, 'id-5');
  });

  test('removing and clearing only touch the list', () async {
    await HistoryStore.add(entry(1));
    await HistoryStore.add(entry(2));

    await HistoryStore.remove('id-1');
    var items = await HistoryStore.load();
    expect(items.map((item) => item.id), ['id-2']);

    await HistoryStore.clear();
    items = await HistoryStore.load();
    expect(items, isEmpty);
  });

  test('a broken saved list is ignored instead of crashing', () async {
    prefs['history_v1'] = '{not json';
    expect(await HistoryStore.load(), isEmpty);
  });

  test('probe options carry height, size and sound flag', () {
    final probe = LinkProbe.fromMap({
      'title': 'Probe',
      'durationMs': 42000,
      'options': [
        {'height': 1080, 'sizeBytes': 9000, 'audio': false},
        {'height': 720, 'sizeBytes': 5000, 'audio': false},
        {'height': 0, 'sizeBytes': 900, 'audio': true},
      ],
    });

    expect(probe.title, 'Probe');
    expect(probe.durationMs, 42000);
    expect(probe.videoOptions.map((option) => option.height), [1080, 720]);
    expect(probe.audioOption?.sizeBytes, 900);
    expect(probe.videoOptions.first.label, '1080p');
    expect(probe.audioOption?.label, 'MP3');
  });

  test('result keeps the gallery URI and the audio kind', () {
    final event = DownloadEvent.fromMap({
      'type': 'done',
      'path': '/tmp/song.mp3',
      'uri': 'content://media/external/audio/media/9',
      'title': 'Song',
      'kind': 'audio',
      'durationMs': 1000,
    });
    final result = VideoResult.fromEvent(event);

    expect(result.isAudio, isTrue);
    expect(result.uri, 'content://media/external/audio/media/9');
    expect(result.title, 'Song');
  });
}
