import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_lite/lucide_icons_lite.dart';
import 'package:save_and_send/src/app.dart';

const _methodChannelName = 'com.personal.save_and_send/native';
const _eventChannelName = 'com.personal.save_and_send/events';

String? _lastRequestId;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
            return null;
          case 'ensureEngine':
            return <String, dynamic>{
              'version': '2025.11.12',
              'cookies': false,
            };
          case 'download':
            _lastRequestId = call.arguments['requestId'] as String?;
            return null;
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
