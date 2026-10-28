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
            return call.arguments['key'] == 'has_run' ? '1' : null;
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
