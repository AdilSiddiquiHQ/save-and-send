import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_lite/lucide_icons_lite.dart';
import 'package:save_and_send/src/app.dart';
import 'package:save_and_send/src/i18n.dart';

const _methodChannelName = 'com.personal.save_and_send/native';
const _eventChannelName = 'com.personal.save_and_send/events';

String? _lastRequestId;
Map<dynamic, dynamic>? _lastDownloadArgs;
Map<dynamic, dynamic>? _lastTransformArgs;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _lastRequestId = null;
    _lastDownloadArgs = null;
    _lastTransformArgs = null;
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
            return null;
          case 'ensureEngine':
            return <String, dynamic>{
              'version': '2025.11.12',
              'cookies': false,
            };
          case 'download':
            _lastRequestId = call.arguments['requestId'] as String?;
            _lastDownloadArgs = call.arguments as Map<dynamic, dynamic>?;
            return null;
          case 'transform':
            _lastTransformArgs = call.arguments as Map<dynamic, dynamic>?;
            return null;
          case 'probe':
            return <String, dynamic>{
              'title': 'A probed clip',
              'durationMs': 42000,
              'thumbnailUrl': null,
              'options': [
                {'height': 1080, 'sizeBytes': 80 * 1024 * 1024, 'audio': false},
                {'height': 720, 'sizeBytes': 34 * 1024 * 1024, 'audio': false},
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

    // EventChannel sends a "listen" method call when Dart subscribes.
    messenger.setMockMethodCallHandler(
      const MethodChannel(_eventChannelName),
      (call) async => null,
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel(_methodChannelName),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(_eventChannelName),
      null,
    );
  });

  testWidgets('idle screen renders in English', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(const SaveAndSendApp());
    await tester.pumpAndSettle();

    expect(
      find.text('Save any video.\nSend it in one tap.'),
      findsOneWidget,
    );
    expect(find.text('Download video'), findsOneWidget);
    expect(find.text('Save & Send'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('download result renders with share actions', (tester) async {
    _setPhone(tester);
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
    expect(id, isNotNull);

    await _emit({'type': 'stage', 'requestId': id, 'stage': 'downloading'});
    await _emit({
      'type': 'progress',
      'requestId': id,
      'percent': 42.0,
      'etaSeconds': 12,
    });
    await tester.pump();
    expect(find.text('42%'), findsOneWidget);

    await _emit({'type': 'gallery', 'requestId': id, 'saved': true});
    await _emit({
      'type': 'done',
      'requestId': id,
      'path': '/tmp/save_and_send_test_missing.mp4',
      'title': 'A test video',
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

    expect(find.text('Ready to send!'), findsOneWidget);
    expect(find.text('Send on WhatsApp'), findsOneWidget);
    expect(find.text('Post to Status'), findsOneWidget);
    expect(find.text('More apps'), findsOneWidget);
    expect(find.text('Saved to your Gallery'), findsOneWidget);
    expect(find.text('0:59'), findsOneWidget);
    expect(find.text('5.0 MB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('splitting a clip lists every Status part', (tester) async {
    _setPhone(tester);
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
      'path': '/tmp/save_and_send_test_missing.mp4',
      'title': 'A long clip',
      'durationMs': 65000,
      'width': 1080,
      'height': 1920,
      'hasAudio': true,
      'trimmed': false,
      'sizeBytes': 12 * 1024 * 1024,
    });
    await tester.pumpAndSettle();

    expect(find.text('For Status'), findsOneWidget);
    await tester.ensureVisible(find.text('Split into parts'));
    await tester.tap(find.text('Split into parts'));
    await tester.pump();
    await tester.pump();

    final transformId = _lastTransformArgs?['requestId'] as String?;
    expect(transformId, isNotNull);
    expect(_lastTransformArgs?['mode'], 'split');

    await _emit({
      'type': 'stage',
      'requestId': transformId,
      'stage': 'transforming',
    });
    await tester.pump();
    expect(find.text('Preparing for Status…'), findsOneWidget);

    await _emit({
      'type': 'transformed',
      'requestId': transformId,
      'items': [
        {
          'path': '/tmp/save_and_send_part_1.mp4',
          'title': 'A long clip · 1',
          'durationMs': 59500,
          'width': 1080,
          'height': 1920,
          'hasAudio': true,
          'sizeBytes': 5 * 1024 * 1024,
          'uri': 'content://media/external/video/media/71',
          'savedPath': '/storage/emulated/0/Movies/part1.mp4',
          'kind': 'video',
        },
        {
          'path': '/tmp/save_and_send_part_2.mp4',
          'title': 'A long clip · 2',
          'durationMs': 5500,
          'width': 1080,
          'height': 1920,
          'hasAudio': true,
          'sizeBytes': 512 * 1024,
          'uri': 'content://media/external/video/media/72',
          'savedPath': '/storage/emulated/0/Movies/part2.mp4',
          'kind': 'video',
        },
      ],
    });
    await tester.pumpAndSettle();

    expect(find.text('PARTS'), findsOneWidget);
    expect(find.text('Parts 1'), findsOneWidget);
    expect(find.text('Parts 2'), findsOneWidget);
    expect(find.text('2 parts saved to your Gallery.'), findsOneWidget);
    expect(find.text('A long clip · 1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Parts 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parts 2'));
    await tester.pumpAndSettle();
    expect(find.text('A long clip · 2'), findsWidgets);
  });

  testWidgets('trim and target size dialogs pass their values', (tester) async {
    _setPhone(tester);
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
      'path': '/tmp/save_and_send_test_missing.mp4',
      'title': 'A test video',
      'durationMs': 60000,
      'width': 1080,
      'height': 1920,
      'hasAudio': true,
      'trimmed': false,
      'sizeBytes': 9 * 1024 * 1024,
    });
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Trim'));
    await tester.tap(find.text('Trim'));
    await tester.pumpAndSettle();
    expect(find.text('Trim the clip'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(_lastTransformArgs?['mode'], 'trim');
    expect(_lastTransformArgs?['startMs'], 0);
    expect(_lastTransformArgs?['endMs'], 59500);

    await _emit({
      'type': 'cancelled',
      'requestId': _lastTransformArgs?['requestId'],
    });
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Make smaller'));
    await tester.tap(find.text('Make smaller'));
    await tester.pumpAndSettle();
    expect(find.text('How small?'), findsOneWidget);
    await tester.tap(find.text('16 MB'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(_lastTransformArgs?['mode'], 'compress');
    expect(_lastTransformArgs?['targetBytes'], 16 * 1024 * 1024);
  });

  testWidgets('Status tools fit a narrow Arabic screen', (tester) async {
    _setPhone(tester, width: 320, height: 640, textScale: 1.3);
    await tester.pumpWidget(const SaveAndSendApp(initialLanguage: 'ar'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'https://www.instagram.com/reel/ABC123/',
    );
    await tester.ensureVisible(find.text('نزّل الفيديو'));
    await tester.tap(find.text('نزّل الفيديو'));
    await tester.pump();
    await tester.pump();

    await _emit({
      'type': 'done',
      'requestId': _lastRequestId,
      'path': '/tmp/missing.mp4',
      'title': 'مقطع طويل',
      'durationMs': 65000,
      'width': 1080,
      'height': 1920,
      'hasAudio': true,
      'trimmed': false,
      'sizeBytes': 12 * 1024 * 1024,
    });
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('للحالة'));
    await tester.pumpAndSettle();
    expect(find.text('للحالة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a link shows sizes and sound-only before downloading',
      (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(const SaveAndSendApp());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'https://www.instagram.com/reel/ABC123/',
    );
    // The probe waits for typing to stop before it runs.
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();

    expect(find.text('A probed clip'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('720p'), findsOneWidget);
    expect(find.text('Sound only'), findsOneWidget);
    expect(find.text('80.0 MB'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Sound only'));
    await tester.tap(find.text('Sound only'));
    await tester.pump();

    await tester.ensureVisible(find.text('Download video'));
    await tester.tap(find.text('Download video'));
    await tester.pump();
    await tester.pump();

    final options = _lastDownloadArgs?['options'] as Map<dynamic, dynamic>?;
    expect(options?['audioOnly'], isTrue);
    expect(options?['maxHeight'], 0);
  });

  testWidgets('sound-only result shows the Music card', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(const SaveAndSendApp());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'https://youtu.be/abc',
    );
    await tester.ensureVisible(find.text('Download video'));
    await tester.tap(find.text('Download video'));
    await tester.pump();
    await tester.pump();

    final id = _lastRequestId;
    expect(id, isNotNull);

    await _emit({
      'type': 'done',
      'requestId': id,
      'path': '/tmp/save_and_send_test_missing.mp3',
      'uri': 'content://media/external/audio/media/42',
      'savedPath': null,
      'title': 'A saved song',
      'durationMs': 185000,
      'width': 0,
      'height': 0,
      'hasAudio': true,
      'kind': 'audio',
      'thumbnailPath': null,
      'thumbnailUrl': null,
      'trimmed': false,
      'sizeBytes': 4 * 1024 * 1024,
    });
    await tester.pumpAndSettle();

    expect(find.text('Sound saved'), findsOneWidget);
    expect(find.text("It's in your phone's Music app."), findsOneWidget);
    expect(find.text('MP3'), findsOneWidget);
    expect(find.text('A saved song'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Urdu UI fits a narrow screen with large text', (tester) async {
    _setPhone(tester, width: 320, height: 640, textScale: 1.3);
    await tester.pumpWidget(
      const SaveAndSendApp(initialLanguage: 'ur'),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('کوئی بھی ویڈیو محفوظ کریں۔\nایک ٹیپ میں بھیجیں۔'),
      findsOneWidget,
    );
    expect(find.text('ویڈیو ڈاؤن لوڈ کریں'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byType(TextField).first,
      'https://youtu.be/abc',
    );
    await tester.ensureVisible(find.text('ویڈیو ڈاؤن لوڈ کریں'));
    await tester.tap(find.text('ویڈیو ڈاؤن لوڈ کریں'));
    await tester.pump();
    await tester.pump();

    final id = _lastRequestId;
    expect(id, isNotNull);

    await _emit({
      'type': 'done',
      'requestId': id,
      'path': '/tmp/save_and_send_test_missing.mp4',
      'title': 'ٹیسٹ ویڈیو',
      'durationMs': 30000,
      'width': 1920,
      'height': 1080,
      'hasAudio': true,
      'thumbnailPath': null,
      'thumbnailUrl': null,
      'trimmed': false,
      'sizeBytes': 2 * 1024 * 1024,
    });
    await tester.pumpAndSettle();

    expect(find.text('بھیجنے کے لیے تیار!'), findsOneWidget);
    expect(find.text('واٹس ایپ پر بھیجیں'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Hindi UI renders on a small screen', (tester) async {
    _setPhone(tester, width: 320, height: 640, textScale: 1.2);
    await tester.pumpWidget(const SaveAndSendApp(initialLanguage: 'hi'));
    await tester.pumpAndSettle();

    expect(
      find.text('कोई भी वीडियो सेव करें।\nएक टैप में भेजें।'),
      findsOneWidget,
    );
    expect(find.text('वीडियो डाउनलोड करें'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic UI mirrors the layout', (tester) async {
    _setPhone(tester, width: 320, height: 640, textScale: 1.2);
    await tester.pumpWidget(const SaveAndSendApp(initialLanguage: 'ar'));
    await tester.pumpAndSettle();

    expect(
      find.text('احفظ أي فيديو.\nوأرسله بضغطة واحدة.'),
      findsOneWidget,
    );
    expect(find.text('نزّل الفيديو'), findsOneWidget);

    final direction = Directionality.of(tester.element(find.byType(Scaffold)));
    expect(direction, TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking a language in settings updates the UI', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(const SaveAndSendApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.settings));
    await tester.pumpAndSettle();

    final hindi = find.text('हिन्दी');
    await tester.ensureVisible(hindi);
    await tester.tap(hindi);
    await tester.pumpAndSettle();

    expect(find.text('वीडियो डाउनलोड करें'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings sheet opens without layout errors', (tester) async {
    _setPhone(tester);
    await tester.pumpWidget(const SaveAndSendApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.settings));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN COOKIES'), findsOneWidget);
    expect(find.text('Update downloader'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(LucideIcons.x).first);
    await tester.pumpAndSettle();
    expect(find.text('LOGIN COOKIES'), findsNothing);
  });

  // The picker wraps onto a second row and the sheet holds long rows, so the
  // tight case is every language on a small screen with large text.
  for (final language in AppLanguage.all) {
    testWidgets('settings fits a narrow ${language.code} screen', (tester) async {
      _setPhone(tester, width: 320, height: 640, textScale: 1.3);
      await tester.pumpWidget(SaveAndSendApp(initialLanguage: language.code));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.settings));
      await tester.pumpAndSettle();

      for (final option in AppLanguage.all) {
        expect(
          find.text(option.label),
          findsOneWidget,
          reason: 'missing ${option.label}',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}

void _setPhone(
  WidgetTester tester, {
  double width = 360,
  double height = 800,
  double textScale = 1.0,
}) {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Future<void> _emit(Map<String, dynamic> event) async {
  final data = const StandardMethodCodec().encodeSuccessEnvelope(event);
  await TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _eventChannelName,
        data,
        (ByteData? _) {},
      );
}
