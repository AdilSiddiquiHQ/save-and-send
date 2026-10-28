import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_lite/lucide_icons_lite.dart';
import 'package:save_and_send/src/app.dart';

const _methodChannelName = 'com.personal.save_and_send/native';
const _eventChannelName = 'com.personal.save_and_send/events';

String? _lastRequestId;
String? _lastTransformId;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final body = FontLoader('Manrope');
    for (final w in [400, 500, 600, 700, 800]) {
      body.addFont(rootBundle.load('assets/fonts/Manrope-$w.ttf'));
    }
    await body.load();

    final display = FontLoader('PlusJakartaSans');
    for (final w in [400, 500, 600, 700, 800]) {
      display.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-$w.ttf'));
    }
    await display.load();

    final urdu = FontLoader('NotoSansArabic');
    for (final w in [400, 500, 600, 700, 800]) {
      urdu.addFont(rootBundle.load('assets/fonts/NotoSansArabic-$w.ttf'));
    }
    // The app leaves non-Arabic scripts to the platform font. The test engine
    // has no platform fonts, so borrow the system ones and register them under
    // the fallback families the theme already asks for.
    for (final (family, path) in const [
      (
        'NotoSansDevanagari',
        '/System/Library/Fonts/Supplemental/Devanagari Sangam MN.ttc',
      ),
      (
        'NotoSansBengali',
        '/System/Library/Fonts/Supplemental/Bangla Sangam MN.ttc',
      ),
    ]) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      await loader.load();
    }
    await urdu.load();

    final icons = FontLoader('packages/lucide_icons_lite/Lucide');
    icons.addFont(rootBundle.load('packages/lucide_icons_lite/assets/lucide.ttf'));
    await icons.load();
  });

  setUp(() {
    _lastRequestId = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel(_methodChannelName),
      (call) async {
        switch (call.method) {
          case 'getInitialShare':
            return <String, dynamic>{};
          case 'getPref':
            final key = call.arguments['key'];
            if (key == 'has_run') return '1';
            if (key == 'history_v1') return _historyJson;
            return null;
          case 'ensureEngine':
            return <String, dynamic>{
              'version': '2025.11.12',
              'cookies': false,
            };
          case 'download':
            _lastRequestId = call.arguments['requestId'] as String?;
            return null;
          case 'transform':
            _lastTransformId = call.arguments['requestId'] as String?;
            return null;
          case 'probe':
            return <String, dynamic>{
              'title': 'A calm evening by the sea',
              'durationMs': 34000,
              'thumbnailUrl': null,
              'options': [
                {'height': 1080, 'sizeBytes': 82 * 1024 * 1024, 'audio': false},
                {'height': 720, 'sizeBytes': 34 * 1024 * 1024, 'audio': false},
                {'height': 480, 'sizeBytes': 12 * 1024 * 1024, 'audio': false},
                {'height': 0, 'sizeBytes': 4 * 1024 * 1024, 'audio': true},
              ],
            };
          case 'engineVersion':
            return '2025.11.12';
          case 'hasCookies':
            return false;
          case 'setCookies':
          case 'saveToGallery':
            return true;
          case 'shareWhatsApp':
          case 'shareStatus':
          case 'shareSystem':
          case 'shareText':
            return 'ok';
          default:
            return null;
        }
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(_eventChannelName),
      (call) async => null,
    );
  });

  testWidgets('idle visual', (tester) async {
    _phone(tester);
    await tester.pumpWidget(const SaveAndSendApp());
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/idle.png'),
    );
  });

  testWidgets('result visual', (tester) async {
    _phone(tester);
    await tester.pumpWidget(const SaveAndSendApp());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'https://www.instagram.com/reel/ABC123/',
    );
    await tester.ensureVisible(find.text('Download video'));
    await tester.tap(find.text('Download video'));
    await tester.pump();
    await tester.pump();
    final id = _lastRequestId;
    await _emit({
      'type': 'done',
      'requestId': id,
      'path': '/tmp/missing.mp4',
      'title': 'A calm evening by the sea',
      'durationMs': 59500,
      'width': 1080,
      'height': 1920,
      'hasAudio': true,
      'thumbnailPath': null,
      'thumbnailUrl': null,
      'trimmed': true,
      'sizeBytes': 5 * 1024 * 1024,
    });
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/result.png'),
    );
  });

  testWidgets('status tools visual', (tester) async {
    _phone(tester);
    await tester.pumpWidget(const SaveAndSendApp());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'https://www.instagram.com/reel/ABC123/',
    );
    await tester.ensureVisible(find.text('Download video'));
    await tester.tap(find.text('Download video'));
    await tester.pump();
    await tester.pump();
    await _emit({
      'type': 'done',
      'requestId': _lastRequestId,
      'path': '/tmp/missing.mp4',
      'title': 'A calm evening by the sea',
      'durationMs': 65000,
      'width': 1280,
      'height': 720,
      'hasAudio': true,
      'thumbnailPath': null,
      'thumbnailUrl': null,
      'trimmed': false,
      'sizeBytes': 12 * 1024 * 1024,
    });
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('For Status'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/status.png'),
    );
  });

  testWidgets('parts visual', (tester) async {
    _phone(tester);
    await tester.pumpWidget(const SaveAndSendApp());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'https://www.instagram.com/reel/ABC123/',
    );
    await tester.ensureVisible(find.text('Download video'));
    await tester.tap(find.text('Download video'));
    await tester.pump();
    await tester.pump();
    final id = _lastRequestId;
    await _emit({
      'type': 'done',
      'requestId': id,
      'path': '/tmp/missing.mp4',
      'title': 'A long clip',
      'durationMs': 65000,
      'width': 1080,
      'height': 1920,
      'hasAudio': true,
      'trimmed': false,
      'sizeBytes': 12 * 1024 * 1024,
    });
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Split into parts'));
    await tester.tap(find.text('Split into parts'));
    await tester.pumpAndSettle();
    await _emit({
      'type': 'transformed',
      'requestId': _lastTransformId,
      'items': [
        {
          'path': '/tmp/part1.mp4',
          'title': 'A long clip · 1',
          'durationMs': 59500,
          'width': 1080,
          'height': 1920,
          'hasAudio': true,
          'sizeBytes': 5 * 1024 * 1024,
          'uri': 'content://media/external/video/media/71',
          'kind': 'video',
        },
        {
          'path': '/tmp/part2.mp4',
          'title': 'A long clip · 2',
          'durationMs': 5500,
          'width': 1080,
          'height': 1920,
          'hasAudio': true,
          'sizeBytes': 512 * 1024,
          'uri': 'content://media/external/video/media/72',
          'kind': 'video',
        },
      ],
    });
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/parts.png'),
    );
  });

  testWidgets('probe visual', (tester) async {
    _phone(tester);
    await tester.pumpWidget(const SaveAndSendApp());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'https://www.instagram.com/reel/ABC123/',
    );
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/probe.png'),
    );
  });

  testWidgets('history visual', (tester) async {
    _phone(tester);
    await tester.pumpWidget(const SaveAndSendApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(LucideIcons.history));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/history.png'),
    );
  });

  testWidgets('settings visual', (tester) async {
    _phone(tester);
    await tester.pumpWidget(const SaveAndSendApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(LucideIcons.settings));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings.png'),
    );
  });

  testWidgets('urdu visual', (tester) async {
    _phone(tester);
    await tester.pumpWidget(const SaveAndSendApp(initialLanguage: 'ur'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/urdu.png'),
    );
  });

  testWidgets('arabic visual', (tester) async {
    _phone(tester);
    await tester.pumpWidget(const SaveAndSendApp(initialLanguage: 'ar'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/arabic.png'),
    );
  });
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _emit(Map<String, dynamic> event) async {
  final data = const StandardMethodCodec().encodeSuccessEnvelope(event);
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(_eventChannelName, data, (ByteData? _) {});
}

const _historyJson = '['
    '{"id":"1","title":"A calm evening by the sea","createdAt":1761600000000,'
    '"sizeBytes":5242880,"durationMs":59000,"kind":"video",'
    '"uri":"content://media/external/video/media/1"},'
    '{"id":"2","title":"The song from that reel","createdAt":1761513600000,'
    '"sizeBytes":4194304,"durationMs":185000,"kind":"audio",'
    '"uri":"content://media/external/audio/media/2"}'
    ']';
