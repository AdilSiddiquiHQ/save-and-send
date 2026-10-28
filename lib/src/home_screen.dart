import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_lite/lucide_icons_lite.dart';
import 'package:video_player/video_player.dart';

import 'design.dart';
import 'history.dart';
import 'i18n.dart';
import 'models.dart';
import 'native.dart';
import 'settings_sheet.dart';
import 'theme.dart';

enum Phase {
  booting,
  idle,
  preparing,
  downloading,
  transforming,
  result,
  error,
  engineError,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.strings,
    required this.language,
    required this.onLanguageChanged,
  });

  final AppLocalizations strings;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Phase _phase = Phase.booting;

  StreamSubscription<DownloadEvent>? _events;
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocus = FocusNode();

  String? _requestId;
  double _progress = 0;
  int _eta = -1;
  String _stage = 'preparing';
  bool _starting = false;

  VideoResult? _result;
  // More than one file when a clip was split for Status.
  List<VideoResult>? _parts;
  int _partIndex = 0;
  String? _errorCode;
  String? _errorMessage;
  String? _errorDetail;
  String? _lastUrl;
  String? _pendingUrl;
  bool _showDetails = false;
  bool _inputError = false;
  bool _gallerySaved = false;
  bool _cancelling = false;
  bool _closing = false;

  bool _engineReady = false;
  bool _firstRun = false;
  String? _engineError;
  Future<bool>? _engineFuture;

  VideoPlayerController? _video;
  bool _videoReady = false;
  bool _videoPaused = false;
  bool _muted = false;

  // Link details read before downloading.
  LinkProbe? _probe;
  bool _probing = false;
  String? _probedUrl;
  int _maxHeight = 0;
  bool _audioOnly = false;
  Timer? _probeDebounce;

  // A link already sitting on the clipboard.
  String? _clipboardUrl;
  String? _dismissedClip;

  bool _wifiOnly = false;
  List<HistoryEntry> _history = const [];

  AppLocalizations get s => widget.strings;
  bool get _busy =>
      _phase == Phase.preparing ||
      _phase == Phase.downloading ||
      _phase == Phase.transforming;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _events = NativeBridge.events.listen(_onEvent);
    _urlController.addListener(_scheduleProbe);
    _bootstrap();
    _loadLocalState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _events?.cancel();
    _probeDebounce?.cancel();
    _urlController.removeListener(_scheduleProbe);
    _urlController.dispose();
    _urlFocus.dispose();
    _video?.dispose();
    if (!_closing) {
      _screen(false);
      NativeBridge.cancel().catchError((Object _) {});
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The user may have copied a new link in another app.
      if (_phase == Phase.idle) unawaited(_readClipboard());
      return;
    }
    final controller = _video;
    if (controller != null && controller.value.isPlaying) {
      unawaited(controller.pause());
      if (mounted) setState(() => _videoPaused = true);
    }
  }

  void _screen(bool on) {
    NativeBridge.setScreenOn(on).catchError((Object _) {});
  }

  // ---------------------------------------------------------------------
  // Startup
  // ---------------------------------------------------------------------

  Future<void> _loadLocalState() async {
    try {
      _wifiOnly = (await NativeBridge.getPref('wifi_only')) == '1';
    } catch (_) {
      // Defaults to off.
    }
    await _loadHistory();
    await _readClipboard();
  }

  Future<void> _loadHistory() async {
    final items = await HistoryStore.load();
    if (mounted) setState(() => _history = items);
  }

  /// Offers a link that is already on the clipboard. It never downloads on its
  /// own; the user still taps.
  Future<void> _readClipboard() async {
    if (_clipboardUrl != null) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final url = _extractUrl(data?.text ?? '');
      if (url == null) return;
      if (_urlController.text.trim().isNotEmpty) return;
      if (url == _lastUrl || url == _dismissedClip) return;
      if (mounted) setState(() => _clipboardUrl = url);
    } catch (_) {
      // Clipboard access can be denied by the system.
    }
  }

  void _useClipboard() {
    final url = _clipboardUrl;
    if (url == null) return;
    setState(() {
      _clipboardUrl = null;
      _dismissedClip = null;
    });
    _urlController.text = url;
    setState(() => _inputError = false);
  }

  void _scheduleProbe() {
    _probeDebounce?.cancel();
    final text = _urlController.text.trim();
    if (text.isEmpty) {
      if (_probe != null || _probing) {
        setState(() {
          _probe = null;
          _probing = false;
          _probedUrl = null;
          _maxHeight = 0;
          _audioOnly = false;
        });
      }
      return;
    }
    if (_busy || text == _probedUrl) return;
    _probeDebounce = Timer(
      const Duration(milliseconds: 900),
      () => _probeLink(text),
    );
  }

  /// Reads duration and per-quality sizes without downloading anything.
  Future<void> _probeLink(String text) async {
    if (_probing || _busy) return;
    final url = _extractUrl(text);
    if (url == null || !_engineReady) return;
    setState(() => _probing = true);
    try {
      final probe = await NativeBridge.probe(url);
      if (!mounted) return;
      if (_urlController.text.trim() != text) return;
      if (probe == null) {
        setState(() => _probing = false);
        return;
      }
      final videos = probe.videoOptions;
      final hasVideo = probe.options.any((option) => !option.audio);
      setState(() {
        _probe = probe;
        _probing = false;
        _probedUrl = text;
        if (hasVideo) {
          _audioOnly = false;
          _maxHeight = videos.isNotEmpty ? videos.first.height : 0;
        } else if (probe.audioOption != null) {
          _audioOnly = true;
          _maxHeight = 0;
        }
      });
    } catch (_) {
      // The download still works without the extra details.
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _bootstrap() async {
    String? sharedUrl;
    String? sharedError;
    try {
      final initial = await NativeBridge.getInitialShare();
      sharedUrl = initial?['url'] as String?;
      sharedError = initial?['error'] as String?;
    } catch (_) {
      // A missing initial share just means the app was opened normally.
    }

    try {
      final seen = await NativeBridge.getPref('has_run');
      if (seen == null) {
        _firstRun = true;
        await NativeBridge.setPref('has_run', '1');
        if (mounted) setState(() {});
      }
    } catch (_) {
      // Not important.
    }

    if (sharedUrl != null && sharedUrl.isNotEmpty) {
      _lastUrl = sharedUrl;
    }

    final ready = await _initEngine();
    if (!mounted) return;

    if (!ready) return;
    if (sharedUrl != null && sharedUrl.isNotEmpty) {
      if (_phase == Phase.booting) await _startDownload(sharedUrl);
    } else if (sharedError != null) {
      if (_phase == Phase.booting) {
        setState(() {
          _phase = Phase.error;
          _errorCode = sharedError;
        });
      }
    } else {
      // A share intent can start a download while the engine is still warming
      // up. Do not overwrite that screen with the idle screen.
      if (_phase == Phase.booting) setState(() => _phase = Phase.idle);
    }
  }

  Future<bool> _initEngine() {
    return _engineFuture ??= _doInitEngine();
  }

  Future<bool> _doInitEngine() async {
    try {
      await NativeBridge.ensureEngine();
      _engineReady = true;
      _engineError = null;
      if (mounted) {
        setState(() {
          // Keep the current screen; only clear the engine error state.
          if (_phase == Phase.engineError) _phase = Phase.booting;
        });
      }
      return true;
    } catch (e) {
      _engineFuture = null;
      _engineReady = false;
      _engineError = e.toString();
      if (mounted) {
        setState(() => _phase = Phase.engineError);
      }
      return false;
    }
  }

  Future<void> _retrySetup() async {
    _engineFuture = null;
    setState(() {
      _phase = Phase.booting;
      _engineError = null;
    });
    final ready = await _initEngine();
    if (!mounted || !ready) return;
    if (_lastUrl != null) {
      await _startDownload(_lastUrl!);
    } else {
      setState(() => _phase = Phase.idle);
    }
  }

  // ---------------------------------------------------------------------
  // Event stream
  // ---------------------------------------------------------------------

  void _onEvent(DownloadEvent event) {
    if (!mounted) return;

    if (event.type == 'share') {
      final url = event.url;
      if (url == null || url.isEmpty) {
        setState(() {
          _phase = Phase.error;
          _errorCode = event.error ?? 'no_link';
        });
        return;
      }
      if (_busy) {
        _pendingUrl = url;
        _snack(s.busy);
      } else {
        _startDownload(url);
      }
      return;
    }

    if (event.requestId != null && event.requestId != _requestId) {
      return;
    }

    switch (event.type) {
      case 'stage':
        setState(() {
          _stage = event.stage ?? _stage;
          if (_stage == 'retrying' || _stage == 'audio') _progress = 0;
          if (_phase == Phase.preparing && _stage != 'preparing') {
            _phase = Phase.downloading;
          }
        });
        break;

      case 'progress':
        final percent = (event.percent ?? 0).clamp(0.0, 100.0);
        setState(() {
          if (percent > _progress) _progress = percent;
          _eta = event.etaSeconds ?? -1;
          if (_phase == Phase.preparing) _phase = Phase.downloading;
        });
        break;

      case 'gallery':
        setState(() => _gallerySaved = event.saved ?? false);
        break;

      case 'done':
        _onDone(event);
        break;

      case 'transformed':
        _onTransformed(event);
        break;

      case 'error':
        _onError(event);
        break;

      case 'cancelled':
        _onCancelled();
        break;
    }
  }

  Future<void> _onDone(DownloadEvent event) async {
    final result = VideoResult.fromEvent(event);
    if (!mounted) return;
    setState(() {
      _phase = Phase.result;
      _result = result;
      _progress = 100;
      _stage = 'saving';
      _videoReady = false;
      _videoPaused = false;
      _muted = false;
      _parts = null;
      _partIndex = 0;
    });
    _screen(false);
    unawaited(HapticFeedback.mediumImpact());
    if (result.uri != null) {
      unawaited(
        HistoryStore.add(HistoryEntry.fromResult(result)).then((_) {
          _loadHistory();
        }),
      );
    }
    if (!result.isAudio) {
      await _startVideo(result);
    }
    if (_pendingUrl != null) {
      _pendingUrl = null;
    }
  }

  void _onError(DownloadEvent event) {
    if (!mounted) return;
    // A failed Status encode should not throw away the finished download.
    if (_phase == Phase.transforming && _result != null) {
      setState(() {
        _phase = Phase.result;
        _progress = 100;
        _stage = 'saving';
        _cancelling = false;
      });
      _screen(false);
      unawaited(HapticFeedback.heavyImpact());
      _snack(s.transformFailed);
      return;
    }
    setState(() {
      _phase = Phase.error;
      _errorCode = event.code ?? 'generic';
      _errorMessage = event.message;
      _errorDetail = event.detail;
      _progress = 0;
      _showDetails = false;
    });
    _screen(false);
    unawaited(HapticFeedback.heavyImpact());
  }

  void _onCancelled() {
    if (!mounted) return;
    if (_phase == Phase.transforming && _result != null) {
      setState(() {
        _phase = Phase.result;
        _progress = 100;
        _stage = 'saving';
        _cancelling = false;
      });
      _screen(false);
      return;
    }
    setState(() {
      _phase = Phase.idle;
      _requestId = null;
      _progress = 0;
      _stage = 'preparing';
      _cancelling = false;
    });
    _screen(false);
  }

  Future<void> _onTransformed(DownloadEvent event) async {
    final thumbnail = _result?.thumbnailPath;
    final thumbnailUrl = _result?.thumbnailUrl;
    final results = event.items
        .map((item) => item.toResult(
              thumbnailPath: thumbnail,
              thumbnailUrl: thumbnailUrl,
            ))
        .where((item) => item.path.isNotEmpty)
        .toList(growable: false);
    if (!mounted) return;
    if (results.isEmpty) {
      setState(() {
        _phase = Phase.result;
        _progress = 100;
        _stage = 'saving';
        _cancelling = false;
      });
      _screen(false);
      _snack(s.transformFailed);
      return;
    }

    final first = results.first;
    setState(() {
      _phase = Phase.result;
      _result = first;
      _parts = results.length > 1 ? results : null;
      _partIndex = 0;
      _gallerySaved = first.uri != null;
      _progress = 100;
      _stage = 'saving';
      _cancelling = false;
    });
    _screen(false);
    unawaited(HapticFeedback.mediumImpact());

    var added = 0;
    // add() inserts at the top, so walk backwards to keep part 1 first.
    for (final item in results.reversed) {
      if (item.uri == null) continue;
      await HistoryStore.add(HistoryEntry.fromResult(item));
      added += 1;
    }
    if (added > 0) unawaited(_loadHistory());

    if (added > 1) {
      _snack(s.partsSaved(added));
    } else if (added == 1) {
      _snack(s.transformDone);
    } else {
      _snack(s.notSavedGallery);
    }
    await _startVideo(first);
  }

  // ---------------------------------------------------------------------
  // Status tools
  // ---------------------------------------------------------------------

  Future<void> _startTransform(
    String mode, {
    int startMs = 0,
    int endMs = 0,
    int targetBytes = 0,
  }) async {
    final result = _result;
    if (result == null || _busy || result.path.isEmpty) return;
    // The card disables these, but a stale result or a direct call should not
    // start an encode that changes nothing.
    if (mode == 'fit' && _alreadyNineSixteen(result)) return;
    if (mode == 'split' && _alreadyShort(result)) return;
    if (mode == 'compress' && _tooSmallToShrink(result)) return;
    final requestId = DateTime.now().microsecondsSinceEpoch.toString();
    await _disposeVideo();
    if (!mounted) return;
    setState(() {
      _phase = Phase.transforming;
      _requestId = requestId;
      _progress = 0;
      _eta = -1;
      _stage = 'transforming';
      _cancelling = false;
    });
    _screen(true);
    try {
      await NativeBridge.transform(
        requestId: requestId,
        path: result.path,
        title: result.title,
        mode: mode,
        startMs: startMs,
        endMs: endMs,
        targetBytes: targetBytes,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = Phase.result;
        _progress = 100;
        _stage = 'saving';
        _cancelling = false;
      });
      _screen(false);
      _snack(e.code == 'BUSY' ? s.busy : s.transformFailed);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = Phase.result;
        _progress = 100;
        _stage = 'saving';
        _cancelling = false;
      });
      _screen(false);
      _snack(s.transformFailed);
    }
  }

  bool _alreadyNineSixteen(VideoResult result) {
    if (result.width <= 0 || result.height <= 0) return false;
    final ratio = result.width / result.height;
    return (ratio - 9 / 16).abs() < 0.02;
  }

  bool _alreadyShort(VideoResult result) =>
      result.durationMs > 0 && result.durationMs <= 59500;

  bool _tooSmallToShrink(VideoResult result) =>
      result.sizeBytes > 0 && result.sizeBytes <= 8 * 1024 * 1024;

  Future<void> _openTrim() async {
    final result = _result;
    if (result == null || result.durationMs < 1000) return;
    final picked = await showDialog<({int startMs, int endMs})>(
      context: context,
      builder: (_) => _TrimDialog(
        strings: s,
        durationMs: result.durationMs,
        path: result.path,
      ),
    );
    if (picked == null || !mounted) return;
    await _startTransform(
      'trim',
      startMs: picked.startMs,
      endMs: picked.endMs,
    );
  }

  Future<void> _openCompress() async {
    final result = _result;
    if (result == null) return;
    final target = await showDialog<int>(
      context: context,
      builder: (_) => _CompressDialog(
        strings: s,
        currentBytes: result.sizeBytes,
        sizeText: _sizeText(result.sizeBytes),
      ),
    );
    if (target == null || !mounted) return;
    await _startTransform('compress', targetBytes: target);
  }

  Future<void> _openPart(int index) async {
    final parts = _parts;
    if (parts == null || index < 0 || index >= parts.length) return;
    final part = parts[index];
    await _disposeVideo();
    if (!mounted) return;
    setState(() {
      _result = part;
      _partIndex = index;
      _gallerySaved = part.uri != null;
    });
    await _startVideo(part);
  }

  // ---------------------------------------------------------------------
  // Download
  // ---------------------------------------------------------------------

  Future<void> _startDownload(String rawUrl, {bool alternate = false}) async {
    if (_starting) return;
    final url = _extractUrl(rawUrl);
    if (url == null) {
      setState(() {
        _phase = Phase.error;
        _errorCode = 'no_link';
        _errorDetail = null;
        _lastUrl = null;
      });
      return;
    }

    if (_wifiOnly && !await _isOnWifi()) {
      _snack(s.wifiNeeded);
      return;
    }

    _starting = true;
    try {
      if (!_engineReady) {
        final ready = await _initEngine();
        if (!mounted || !ready) return;
      }

      await _disposeVideo();
      if (!mounted) return;
      final requestId = DateTime.now().microsecondsSinceEpoch.toString();

      setState(() {
        _phase = Phase.preparing;
        _requestId = requestId;
        _progress = 0;
        _eta = -1;
        _stage = 'preparing';
        _result = null;
        _errorCode = null;
        _errorMessage = null;
        _errorDetail = null;
        _gallerySaved = false;
        _showDetails = false;
        _cancelling = false;
        _inputError = false;
        _lastUrl = url;
        _urlController.text = url;
        _parts = null;
        _partIndex = 0;
      });
      _urlFocus.unfocus();

      try {
        _screen(true);
        await NativeBridge.download(
          url: url,
          requestId: requestId,
          maxHeight: _audioOnly ? 0 : _maxHeight,
          audioOnly: _audioOnly,
          alternate: alternate,
        );
      } on PlatformException catch (e) {
        if (!mounted) return;
        setState(() {
          _phase = Phase.error;
          _errorCode = e.code == 'BUSY' ? 'busy' : 'engine';
          _errorDetail = e.details?.toString();
        });
        _screen(false);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _phase = Phase.error;
          _errorCode = 'engine';
          _errorDetail = e.toString();
        });
        _screen(false);
      }
    } finally {
      _starting = false;
    }
  }

  Future<bool> _isOnWifi() async {
    try {
      return await NativeBridge.isOnWifi();
    } catch (_) {
      return true;
    }
  }

  Future<void> _lastUrlAgain() async {
    final url = _lastUrl;
    if (url == null) return;
    await _startDownload(url, alternate: true);
  }

  Future<void> _cancelDownload() async {
    final transforming = _phase == Phase.transforming;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(transforming ? s.cancelTransformTitle : s.cancelTitle),
          content: Text(transforming ? s.cancelTransformBody : s.cancelBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(transforming ? s.keepEncoding : s.keepDownloading),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: kRed,
                minimumSize: const Size(100, 48),
              ),
              child: Text(s.stop),
            ),
          ],
        );
      },
    );
    if (yes != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await NativeBridge.cancel();
    } catch (_) {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<void> _confirmExit() async {
    if (!_busy) return;
    final transforming = _phase == Phase.transforming;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(transforming ? s.cancelTransformTitle : s.cancelTitle),
          content: Text(transforming ? s.cancelTransformBody : s.cancelBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(transforming ? s.keepEncoding : s.keepDownloading),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: kRed,
                minimumSize: const Size(100, 48),
              ),
              child: Text(s.stop),
            ),
          ],
        );
      },
    );
    if (yes != true) return;
    try {
      await NativeBridge.cancel();
    } catch (_) {
      // The app is closing anyway.
    }
    if (!mounted) return;
    // PopScope still reports busy here, so Navigator.maybePop() would show
    // this dialog again. Close the activity directly instead.
    await SystemNavigator.pop();
  }

  Future<void> _done() async {
    _closing = true;
    await _disposeVideo();
    try {
      await NativeBridge.closeApp();
    } catch (_) {
      // The activity may already be closing.
    }
  }

  // ---------------------------------------------------------------------
  // Preview
  // ---------------------------------------------------------------------

  Future<void> _startVideo(VideoResult result) async {
    await _disposeVideo();
    if (result.path.isEmpty || !File(result.path).existsSync()) {
      if (mounted) setState(() => _videoReady = false);
      return;
    }

    final controller = VideoPlayerController.file(File(result.path));
    final canPlay = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      if (canPlay) {
        await controller.play();
      } else {
        await controller.pause();
      }
      if (!mounted) {
        try {
          await controller.dispose();
        } catch (_) {}
        return;
      }
      setState(() {
        _video = controller;
        _videoReady = true;
        _videoPaused = !canPlay;
      });
    } catch (_) {
      try {
        await controller.dispose();
      } catch (_) {}
      if (mounted) setState(() => _videoReady = false);
    }
  }

  Future<void> _disposeVideo() async {
    final controller = _video;
    _video = null;
    if (mounted) {
      setState(() {
        _videoReady = false;
        _videoPaused = false;
      });
    }
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {
        // The platform player may already be gone.
      }
    }
  }

  Future<void> _toggleMute() async {
    final controller = _video;
    if (controller == null) return;
    setState(() => _muted = !_muted);
    await controller.setVolume(_muted ? 0 : 1);
  }

  Future<void> _togglePlay() async {
    final controller = _video;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
      if (mounted) setState(() => _videoPaused = true);
    } else {
      await controller.play();
      if (mounted) setState(() => _videoPaused = false);
    }
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final url = _extractUrl(data?.text ?? '');
      if (url == null) {
        _snack(s.errNoLink);
        return;
      }
      _urlController.text = url;
      setState(() => _inputError = false);
    } catch (_) {
      _snack(s.errNoLink);
    }
  }

  void _submit() {
    final url = _extractUrl(_urlController.text);
    if (url == null) {
      setState(() => _inputError = true);
      _urlFocus.requestFocus();
      return;
    }
    setState(() {
      _inputError = false;
      _clipboardUrl = null;
    });
    _startDownload(url);
  }

  Future<void> _shareWhatsApp() async {
    final result = _result;
    if (result == null) return;
    try {
      final uri = result.uri;
      final response = uri != null
          ? await NativeBridge.shareWhatsAppUri(uri, _mimeFor(result))
          : await NativeBridge.shareWhatsApp(result.path);
      if (!mounted) return;
      if (response == 'not_installed') {
        _snack(s.whatsappMissing);
      } else if (response != 'ok') {
        _snack(s.shareFailed);
      }
    } catch (_) {
      if (mounted) _snack(s.shareFailed);
    }
  }

  Future<void> _shareStatus() async {
    final result = _result;
    if (result == null) return;
    try {
      final uri = result.uri;
      final response = uri != null
          ? await NativeBridge.shareStatusUri(uri, _mimeFor(result))
          : await NativeBridge.shareStatus(result.path);
      if (!mounted) return;
      if (response == 'chat') {
        _snack(s.statusFallback);
      } else if (response == 'not_installed') {
        _snack(s.whatsappMissing);
      } else if (response != 'ok') {
        _snack(s.shareFailed);
      }
    } catch (_) {
      if (mounted) _snack(s.shareFailed);
    }
  }

  Future<void> _shareSystem() async {
    final result = _result;
    if (result == null) return;
    try {
      final uri = result.uri;
      final response = uri != null
          ? await NativeBridge.shareSystemUri(uri, _mimeFor(result))
          : await NativeBridge.shareSystem(result.path);
      if (!mounted) return;
      if (response != 'ok') _snack(s.shareFailed);
    } catch (_) {
      if (mounted) _snack(s.shareFailed);
    }
  }

  Future<void> _saveAgain() async {
    final result = _result;
    if (result == null) return;
    try {
      final saved = await NativeBridge.saveToGallery(result.path);
      if (!mounted) return;
      setState(() => _gallerySaved = saved);
      if (!saved) _snack(s.galleryPermission);
    } catch (_) {
      if (mounted) _snack(s.galleryPermission);
    }
  }

  Future<void> _shareLink() async {
    final url = _lastUrl;
    if (url == null) return;
    try {
      final response = await NativeBridge.shareText(url);
      if (!mounted) return;
      if (response != 'ok') _snack(s.shareFailed);
    } catch (_) {
      if (mounted) _snack(s.shareFailed);
    }
  }

  void _retry() {
    final url = _lastUrl;
    if (url == null) {
      setState(() {
        _phase = Phase.idle;
        _errorCode = null;
        _errorDetail = null;
      });
      return;
    }
    _startDownload(url);
  }

  Future<void> _openSettings() async {
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: kInk.withValues(alpha: 0.34),
        builder: (_) {
          return SettingsSheet(
            strings: widget.strings,
            language: widget.language,
            busy: _busy,
            diagnosticUrl: _lastUrl ?? _extractUrl(_urlController.text),
            onLanguageChanged: widget.onLanguageChanged,
          );
        },
      );
    } catch (_) {
      // The sheet is optional; never let it take down the screen.
    }
    // Wi-Fi only may have changed while the sheet was open.
    if (mounted) await _loadLocalState();
  }

  Future<void> _openHistory() async {
    await _loadHistory();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: kInk.withValues(alpha: 0.34),
      builder: (_) => _HistorySheet(
        strings: s,
        items: _history,
        onChanged: _loadHistory,
      ),
    );
  }

  Future<void> _runDiagnostics() async {
    final url = _lastUrl ?? _extractUrl(_urlController.text);
    if (url == null) {
      _snack(s.diagnosticsNoLink);
      return;
    }
    await showDiagnosticsDialog(context, s, url);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String? _extractUrl(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final direct = RegExp(
      r"""https?://[^\s<>"']+""",
      caseSensitive: false,
    ).firstMatch(trimmed)?.group(0);

    // Hosts people actually paste. A full https:// link is accepted for any
    // site yt-dlp knows; this list only covers bare links without a scheme.
    final bare = direct ??
        RegExp(
          r"""(?:https?://)?(?:www\.|m\.|web\.|v\.)?(?:instagram\.com|instagr\.am|ig\.me|facebook\.com|fb\.watch|fb\.com|youtube\.com|youtu\.be|youtube-nocookie\.com|tiktok\.com|vm\.tiktok\.com|vt\.tiktok\.com|twitter\.com|x\.com|threads\.net|reddit\.com|redd\.it|vimeo\.com|dailymotion\.com|dai\.ly|twitch\.tv|clips\.twitch\.tv|soundcloud\.com|pinterest\.com|pin\.it|snapchat\.com|rumble\.com|streamable\.com|bilibili\.com|b23\.tv|vk\.com|ok\.ru|likee\.video|sharechat\.com|moj\.video|linkedin\.com|imgur\.com|giphy\.com)/[^\s<>"']+""",
          caseSensitive: false,
        ).firstMatch(trimmed)?.group(0);

    if (bare == null || bare.isEmpty) return null;
    final withScheme = bare.toLowerCase().startsWith('http')
        ? bare
        : 'https://$bare';
    final cleaned = withScheme.replaceAll(RegExp(r'[),.;!>"]+$'), '');
    return _normalizeSocialUrl(cleaned);
  }

  String _normalizeSocialUrl(String url) {
    // 1. Instagram share links (e.g. /share/reel/ID -> /reel/ID/)
    final instaShare = RegExp(
      r"""(?:https?://)?(?:www\.)?instagram\.com/share/(reel|reels|p|tv)/([^/?#&]+)""",
      caseSensitive: false,
    ).firstMatch(url);
    if (instaShare != null) {
      final rawType = instaShare.group(1)?.toLowerCase();
      final type = rawType == 'reels' ? 'reel' : rawType;
      final id = instaShare.group(2);
      return 'https://www.instagram.com/$type/$id/';
    }

    // 2. Facebook share links (only direct digits should be rewritten immediately;
    // alphanumeric share tokens must stay intact for native crawler resolution)
    final fbShareReel = RegExp(
      r"""(?:https?://)?(?:www\.|m\.)?facebook\.com/share/r/([^/?#&]+)""",
      caseSensitive: false,
    ).firstMatch(url);
    if (fbShareReel != null) {
      final id = fbShareReel.group(1);
      if (id != null && RegExp(r'^\d+$').hasMatch(id)) {
        return 'https://www.facebook.com/reel/$id/';
      }
      return url;
    }

    final fbShareVideo = RegExp(
      r"""(?:https?://)?(?:www\.|m\.)?facebook\.com/share/v/([^/?#&]+)""",
      caseSensitive: false,
    ).firstMatch(url);
    if (fbShareVideo != null) {
      final id = fbShareVideo.group(1);
      if (id != null && RegExp(r'^\d+$').hasMatch(id)) {
        return 'https://www.facebook.com/watch/?v=$id';
      }
      return url;
    }

    return url;
  }

  String _errorText() {
    final localized = s.errorFor(_errorCode);
    if (localized != null) return localized;
    if (_errorMessage != null && _errorMessage!.trim().isNotEmpty) {
      return _errorMessage!;
    }
    return s.errGeneric;
  }

  String _etaText(int seconds) {
    if (seconds <= 0) return '';
    final m = seconds ~/ 60;
    final sec = seconds % 60;
    final value = m > 0 ? '$m:${sec.toString().padLeft(2, '0')}' : '${sec}s';
    return s.timeLeft(value);
  }

  String _durationText(int ms) {
    if (ms <= 0) return '—';
    final total = (ms / 1000).floor();
    final m = total ~/ 60;
    final sec = total % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  String _sizeText(int bytes) {
    if (bytes <= 0) return s.sizeUnknown;
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _mimeFor(VideoResult result) =>
      result.isAudio ? 'audio/mpeg' : 'video/mp4';

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AppBackground(
          child: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: KeyedSubtree(
                key: ValueKey(_busy ? 'downloading' : _phase.name),
                child: _buildBody(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case Phase.booting:
        return _buildBoot();
      case Phase.idle:
        return _buildIdle();
      case Phase.preparing:
      case Phase.downloading:
      case Phase.transforming:
        return _buildDownloading();
      case Phase.result:
        return _buildResult();
      case Phase.error:
        return _buildError();
      case Phase.engineError:
        return _buildEngineError();
    }
  }

  Widget _buildBoot() {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(size: 82),
              const SizedBox(height: 24),
              Text(
                s.appName,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineLarge,
              ),
              const SizedBox(height: 7),
              Text(
                s.appSubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: kMuted),
              ),
              const SizedBox(height: 34),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  strokeCap: StrokeCap.round,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _firstRun ? s.preparingFirst : s.preparing,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: kMuted,
                  height: 1.55,
                ),
              ),
              if (_firstRun) ...[
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: kSurface.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: kLine),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.sparkles,
                        size: 14,
                        color: kAmber,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          s.firstTime,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: kMuted,
                            letterSpacing: 0.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdle() {
    final theme = Theme.of(context);
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AppHeader(
            strings: s,
            onSettings: _openSettings,
            onHistory: _openHistory,
            historyCount: _history.length,
          ),
          const SizedBox(height: 26),
          Text(
            s.heroEyebrow.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: kGreen,
              letterSpacing: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(s.tagline, style: theme.textTheme.displaySmall),
          const SizedBox(height: 10),
          Text(
            s.taglineSub,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: kMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MetaPill(
                icon: LucideIcons.lock,
                label: s.trustPrivate,
                background: kSurface.withValues(alpha: 0.85),
              ),
              MetaPill(
                icon: LucideIcons.shieldCheck,
                label: s.trustNoAccount,
                background: kSurface.withValues(alpha: 0.85),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _LinkComposer(
            strings: s,
            controller: _urlController,
            focusNode: _urlFocus,
            inputError: _inputError,
            onPaste: _paste,
            onSubmit: _submit,
            onChanged: () {
              if (_inputError) setState(() => _inputError = false);
            },
          ),
          if (_clipboardUrl != null) ...[
            const SizedBox(height: 12),
            _ClipboardCard(
              strings: s,
              url: _clipboardUrl!,
              onUse: _useClipboard,
              onDismiss: () => setState(() {
                _dismissedClip = _clipboardUrl;
                _clipboardUrl = null;
              }),
            ),
          ],
          if (_probing || _probe != null) ...[
            const SizedBox(height: 12),
            _QualityPicker(
              strings: s,
              probe: _probe,
              probing: _probing,
              audioOnly: _audioOnly,
              maxHeight: _maxHeight,
              onChanged: (audioOnly, maxHeight) {
                setState(() {
                  _audioOnly = audioOnly;
                  _maxHeight = maxHeight;
                });
              },
            ),
          ],
          const SizedBox(height: 13),
          Text(
            s.worksWith,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: kMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 28),
          SectionHeading(
            title: s.howItWorks,
            subtitle: s.howItWorksHelp,
          ),
          const SizedBox(height: 12),
          _StepsCard(
            step1Title: s.step1Title,
            step1Body: s.step1Body,
            step2Title: s.step2Title,
            step2Body: s.step2Body,
            step3Title: s.step3Title,
            step3Body: s.step3Body,
          ),
        ],
      ),
    );
  }

  Widget _buildDownloading() {
    final theme = Theme.of(context);
    final preparing = _phase == Phase.preparing;
    final transforming = _phase == Phase.transforming;
    final value = (_progress / 100).clamp(0.0, 1.0);
    final stage = s.stageFor(_stage);
    final percentLabel = preparing ? '—' : '${_progress.round()}%';
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AppHeader(strings: s),
          const SizedBox(height: 26),
          SurfaceCard(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (transforming ? s.statusTools : s.progressEyebrow)
                            .toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: kGreen,
                        ),
                      ),
                    ),
                    if (!preparing && _eta > 0)
                      MetaPill(
                        icon: LucideIcons.clock,
                        label: _etaText(_eta),
                        background: kSurfaceMuted,
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                _ProgressRing(
                  value: preparing ? null : value,
                  label: percentLabel,
                ),
                const SizedBox(height: 18),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    stage,
                    key: ValueKey(stage),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _iconForStage(_stage),
                      size: 15,
                      color: kMuted,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        preparing ? s.preparing : s.statusNote,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: kMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: preparing ? null : value,
                    minHeight: 8,
                    backgroundColor: kBrandTint,
                  ),
                ),
                const SizedBox(height: 18),
                NoteBanner(
                  icon: LucideIcons.info,
                  text: transforming ? s.statusToolsHelp : s.progressHelp,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DepthButton(
            tone: DepthTone.secondary,
            icon: LucideIcons.x,
            label: s.cancel,
            busy: _cancelling,
            onPressed: _cancelling ? null : _cancelDownload,
          ),
          const SizedBox(height: 4),
          Text(
            s.statusNote,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: kMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final result = _result;
    if (result == null) return _buildIdle();
    final theme = Theme.of(context);

    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ResultHeader(strings: s, onClose: _done),
          if (_parts != null && _parts!.length > 1) ...[
            const SizedBox(height: 14),
            _PartsCard(
              strings: s,
              parts: _parts!,
              selected: _partIndex,
              onSelect: _openPart,
            ),
          ],
          const SizedBox(height: 16),
          _Preview(
            result: result,
            controller: _videoReady ? _video : null,
            muted: _muted,
            paused: _videoPaused,
            onToggleMute: _toggleMute,
            onTogglePlay: _togglePlay,
            strings: s,
          ),
          const SizedBox(height: 16),
          SurfaceCard(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 11),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    MetaPill(
                      icon: LucideIcons.clock,
                      label: _durationText(result.durationMs),
                    ),
                    MetaPill(
                      icon: LucideIcons.hardDrive,
                      label: _sizeText(result.sizeBytes),
                    ),
                    if (result.isAudio)
                      MetaPill(
                        icon: LucideIcons.music,
                        label: 'MP3',
                        foreground: kGreen,
                        background: kBrandTint,
                        borderColor: kBrandTint,
                      )
                    else
                      MetaPill(
                        icon: result.hasAudio
                            ? LucideIcons.volume2
                            : LucideIcons.volumeX,
                        label: result.hasAudio ? s.sound : s.noSound,
                        foreground: result.hasAudio ? kGreen : kAmber,
                        background:
                            result.hasAudio ? kBrandTint : kAmberTint,
                        borderColor:
                            result.hasAudio ? kBrandTint : kAmberTint,
                      ),
                  ],
                ),
                if (result.trimmed) ...[
                  const SizedBox(height: 12),
                  NoteBanner(
                    icon: LucideIcons.scissors,
                    text: s.trimmedNote,
                    foreground: const Color(0xFF7A4E14),
                    background: kAmberTint,
                    borderColor: const Color(0xFFF0DFC3),
                  ),
                ],
                const SizedBox(height: 13),
                const Divider(),
                const SizedBox(height: 9),
                _GalleryRow(
                  saved: _gallerySaved,
                  savedText: result.isAudio ? s.audioBody : s.savedGallery,
                  missingText: s.notSavedGallery,
                  saveText: s.saveGallery,
                  onSave: _saveAgain,
                ),
              ],
            ),
          ),
          if (!result.isAudio) ...[
            const SizedBox(height: 18),
            _StatusToolsCard(
              strings: s,
              onFit: () => _startTransform('fit'),
              onSplit: () => _startTransform('split'),
              onTrim: _openTrim,
              onCompress: _openCompress,
              fitBlocked:
                  _alreadyNineSixteen(result) ? s.alreadyFit : null,
              splitBlocked: _alreadyShort(result) ? s.alreadyShort : null,
              trimBlocked:
                  result.durationMs > 0 && result.durationMs < 2000
                      ? s.tooShortTrim
                      : null,
              compressBlocked:
                  _tooSmallToShrink(result) ? s.alreadySmall : null,
            ),
          ],
          const SizedBox(height: 23),
          SectionHeading(
            title: s.sendSection,
            subtitle: s.sendHelp,
          ),
          const SizedBox(height: 12),
          DepthButton(
            tone: DepthTone.whatsapp,
            icon: LucideIcons.messageCircle,
            label: s.sendWhatsApp,
            onPressed: _shareWhatsApp,
          ),
          const SizedBox(height: 10),
          DepthButton(
            tone: DepthTone.secondary,
            icon: LucideIcons.circlePlus,
            label: s.sendStatus,
            onPressed: _shareStatus,
          ),
          const SizedBox(height: 10),
          DepthButton(
            tone: DepthTone.quiet,
            icon: LucideIcons.share2,
            label: s.moreApps,
            onPressed: _shareSystem,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _done,
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: kMuted,
            ),
            child: Text(s.done),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    final theme = Theme.of(context);
    final hasLink = _lastUrl != null;
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SoftIconButton(
              icon: LucideIcons.x,
              onPressed: _done,
              tooltip: s.done,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: EmptyStateIcon(
              icon: LucideIcons.triangleAlert,
              color: kRed,
              background: kDangerTint,
              size: 72,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            s.errorTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 9),
          Text(
            _errorText(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: kMuted,
              height: 1.5,
            ),
          ),
          if (hasLink) ...[
            const SizedBox(height: 16),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              color: kSurface.withValues(alpha: 0.72),
              shadow: false,
              child: Row(
                children: [
                  const Icon(LucideIcons.link2, size: 16, color: kMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _lastUrl!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: kMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          if (_errorCode == 'login') ...[
            DepthButton(
              tone: DepthTone.primary,
              icon: LucideIcons.keyRound,
              label: s.loginCookies,
              onPressed: _openSettings,
            ),
            const SizedBox(height: 10),
          ],
          if (hasLink) ...[
            DepthButton(
              icon: LucideIcons.refreshCw,
              label: s.tryAgain,
              onPressed: _retry,
            ),
            const SizedBox(height: 10),
            DepthButton(
              tone: DepthTone.secondary,
              icon: LucideIcons.rotateCcw,
              label: s.tryAnotherWay,
              onPressed: _lastUrlAgain,
            ),
            const SizedBox(height: 10),
            DepthButton(
              tone: DepthTone.secondary,
              icon: LucideIcons.share2,
              label: s.shareLink,
              onPressed: _shareLink,
            ),
            const SizedBox(height: 10),
            DepthButton(
              tone: DepthTone.quiet,
              icon: LucideIcons.stethoscope,
              label: s.diagnosticsRun,
              onPressed: _runDiagnostics,
            ),
            const SizedBox(height: 10),
          ],
          DepthButton(
            tone: DepthTone.quiet,
            icon: LucideIcons.settings,
            label: s.openSettings,
            onPressed: _openSettings,
          ),
          const SizedBox(height: 2),
          TextButton(
            onPressed: _done,
            style: TextButton.styleFrom(foregroundColor: kMuted),
            child: Text(s.done),
          ),
          if (_errorDetail != null && _errorDetail!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _showDetails = !_showDetails),
                style: TextButton.styleFrom(foregroundColor: kMuted),
                icon: Icon(
                  _showDetails
                      ? LucideIcons.chevronUp
                      : LucideIcons.chevronDown,
                  size: 16,
                ),
                label: Text(
                  _showDetails ? s.hideDetails : s.details,
                ),
              ),
            ),
            if (_showDetails)
              SurfaceCard(
                padding: const EdgeInsets.all(14),
                color: kSurfaceMuted,
                shadow: false,
                child: SelectableText(
                  _errorDetail!,
                  // The detail is a native log line, always left to right.
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.4,
                    color: kMuted,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildEngineError() {
    final theme = Theme.of(context);
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SoftIconButton(
              icon: LucideIcons.x,
              onPressed: _done,
              tooltip: s.done,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: EmptyStateIcon(
              icon: LucideIcons.cloudDownload,
              color: kAmber,
              background: kAmberTint,
              size: 74,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            s.engineErrorTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          Text(
            s.engineErrorBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: kMuted,
              height: 1.5,
            ),
          ),
          if (_engineError != null) ...[
            const SizedBox(height: 14),
            SurfaceCard(
              padding: const EdgeInsets.all(13),
              color: kSurface.withValues(alpha: 0.72),
              shadow: false,
              child: Text(
                _engineError!,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                // Native setup output is always left to right.
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.4,
                  color: kMuted,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          DepthButton(
            icon: LucideIcons.refreshCw,
            label: s.retrySetup,
            onPressed: _retrySetup,
          ),
          const SizedBox(height: 2),
          TextButton(
            onPressed: _done,
            style: TextButton.styleFrom(foregroundColor: kMuted),
            child: Text(s.done),
          ),
        ],
      ),
    );
  }

  IconData _iconForStage(String stage) {
    switch (stage) {
      case 'downloading':
        return LucideIcons.download;
      case 'audio':
      case 'merging':
        return LucideIcons.music;
      case 'optimizing':
      case 'trimming':
        return LucideIcons.scissors;
      case 'retrying':
        return LucideIcons.refreshCw;
      case 'saving':
        return LucideIcons.hardDrive;
      default:
        return LucideIcons.cloudDownload;
    }
  }
}

// ---------------------------------------------------------------------------
// Screen pieces
// ---------------------------------------------------------------------------

class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.strings,
    this.onSettings,
    this.onHistory,
    this.historyCount = 0,
  });

  final AppLocalizations strings;
  final VoidCallback? onSettings;
  final VoidCallback? onHistory;
  final int historyCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const BrandMark(size: 44),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.appName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontFamily: kFontDisplay,
                  fontFamilyFallback: kFontFallback,
                  fontSize: 18,
                  letterSpacing: -0.15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                strings.appSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: kMuted),
              ),
            ],
          ),
        ),
        if (onHistory != null) ...[
          const SizedBox(width: 6),
          Stack(
            clipBehavior: Clip.none,
            children: [
              SoftIconButton(
                icon: LucideIcons.history,
                onPressed: onHistory,
                tooltip: strings.recent,
              ),
              if (historyCount > 0)
                PositionedDirectional(
                  top: 7,
                  end: 7,
                  child: IgnorePointer(
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: kGreen,
                        shape: BoxShape.circle,
                        border: Border.all(color: kSurface, width: 1.6),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (onSettings != null) ...[
          const SizedBox(width: 6),
          SoftIconButton(
            icon: LucideIcons.settings,
            onPressed: onSettings,
            tooltip: strings.settings,
          ),
        ],
      ],
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.strings, required this.onClose});

  final AppLocalizations strings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: kBrandTint,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD8E9DE)),
          ),
          child: const Icon(LucideIcons.circleCheck, color: kGreen, size: 22),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.readyTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                strings.readySubtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: kMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SoftIconButton(
          icon: LucideIcons.x,
          onPressed: onClose,
          tooltip: strings.done,
        ),
      ],
    );
  }
}

class _LinkComposer extends StatelessWidget {
  const _LinkComposer({
    required this.strings,
    required this.controller,
    required this.focusNode,
    required this.inputError,
    required this.onPaste,
    required this.onSubmit,
    required this.onChanged,
  });

  final AppLocalizations strings;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool inputError;
  final VoidCallback onPaste;
  final VoidCallback onSubmit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: kBrandTint,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: const Color(0xFFD4E6DA),
                    width: 1.0,
                  ),
                ),
                child: const Icon(LucideIcons.film, color: kGreen, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.linkLabel,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      strings.linkHelp,
                      style: theme.textTheme.bodySmall?.copyWith(color: kMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Material(
                color: kSurfaceMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: kLine),
                ),
                child: InkWell(
                  onTap: onPaste,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6.5,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.clipboardPaste,
                          size: 14,
                          color: kDeepGreen,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          strings.paste,
                          style: const TextStyle(
                            fontFamily: kFontBody,
                            fontFamilyFallback: kFontFallback,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: kDeepGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => onSubmit(),
            onChanged: (_) => onChanged(),
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14.5),
            textAlign: TextAlign.left,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              hintText: '\u2066${strings.pasteHint}\u2069',
              prefixIcon: const Icon(LucideIcons.link2, size: 17),
              errorText: inputError ? strings.errNoLink : null,
            ),
          ),
          const SizedBox(height: 12),
          DepthButton(
            icon: LucideIcons.arrowDownToLine,
            label: strings.download,
            onPressed: onSubmit,
          ),
          const SizedBox(height: 3),
          Text(
            strings.downloadHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: kMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepsCard extends StatelessWidget {
  const _StepsCard({
    required this.step1Title,
    required this.step1Body,
    required this.step2Title,
    required this.step2Body,
    required this.step3Title,
    required this.step3Body,
  });

  final String step1Title;
  final String step1Body;
  final String step2Title;
  final String step2Body;
  final String step3Title;
  final String step3Body;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Column(
        children: [
          _StepRow(
            number: '01',
            icon: LucideIcons.share2,
            title: step1Title,
            body: step1Body,
          ),
          const Divider(),
          _StepRow(
            number: '02',
            icon: LucideIcons.cloudDownload,
            title: step2Title,
            body: step2Body,
          ),
          const Divider(),
          _StepRow(
            number: '03',
            icon: LucideIcons.send,
            title: step3Title,
            body: step3Body,
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
  });

  final String number;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kSurfaceMuted,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kLine),
            ),
            child: Text(
              number,
              style: theme.textTheme.labelSmall?.copyWith(
                color: kMuted,
                letterSpacing: 0.2,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kBrandTint,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: const Color(0xFFD4E6DA),
                width: 1.0,
              ),
            ),
            child: Icon(icon, size: 17, color: kGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2.5),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: kMuted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.value, required this.label});

  final double? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const size = 152.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (value == null)
            const SizedBox.expand(
              child: CircularProgressIndicator(
                strokeWidth: 8.5,
                strokeCap: StrokeCap.round,
                backgroundColor: kBrandTint,
              ),
            )
          else
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: value!),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              builder: (context, animated, child) {
                return SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: animated,
                    strokeWidth: 8.5,
                    strokeCap: StrokeCap.round,
                    backgroundColor: kBrandTint,
                  ),
                );
              },
            ),
          Container(
            width: 102,
            height: 102,
            decoration: BoxDecoration(
              color: kSurface,
              shape: BoxShape.circle,
              border: Border.all(color: kLine, width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F1A14).withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                label,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontSize: 29,
                  letterSpacing: -0.9,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.result,
    required this.controller,
    required this.muted,
    required this.paused,
    required this.onToggleMute,
    required this.onTogglePlay,
    required this.strings,
  });

  final VideoResult result;
  final VideoPlayerController? controller;
  final bool muted;
  final bool paused;
  final VoidCallback onToggleMute;
  final VoidCallback onTogglePlay;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    if (result.isAudio) return _AudioCard(result: result, strings: strings);
    return LayoutBuilder(
      builder: (context, constraints) {
        const maxHeight = 300.0;
        var width = constraints.maxWidth;
        var height = width / result.aspectRatio;
        if (height > maxHeight) {
          height = maxHeight;
          width = height * result.aspectRatio;
        }

        return Center(
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kLineStrong, width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F1A14).withValues(alpha: 0.10),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19),
              child: ColoredBox(
                color: const Color(0xFF0A140F),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (controller != null)
                      VideoPlayer(controller!)
                    else if (result.thumbnailPath != null &&
                        File(result.thumbnailPath!).existsSync())
                      Image.file(
                        File(result.thumbnailPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _placeholder(),
                      )
                    else
                      _placeholder(),
                    if (controller != null) ...[
                      Positioned(
                        top: 9,
                        right: 9,
                        child: _VideoControl(
                          icon: muted
                              ? LucideIcons.volumeX
                              : LucideIcons.volume2,
                          tooltip:
                              muted ? strings.unmute : strings.mute,
                          onPressed: onToggleMute,
                        ),
                      ),
                      if (paused)
                        Center(
                          child: _VideoControl(
                            icon: LucideIcons.play,
                            tooltip: strings.play,
                            onPressed: onTogglePlay,
                            size: 52,
                            iconSize: 22,
                          ),
                        )
                      else
                        Positioned(
                          bottom: 9,
                          left: 9,
                          child: _VideoControl(
                            icon: LucideIcons.pause,
                            tooltip: strings.pause,
                            onPressed: onTogglePlay,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _placeholder() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF183A2C), Color(0xFF0B1410)],
        ),
      ),
      child: Center(
        child: Icon(
          LucideIcons.circlePlay,
          color: Colors.white70,
          size: 48,
        ),
      ),
    );
  }
}

class _VideoControl extends StatelessWidget {
  const _VideoControl({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 38,
    this.iconSize = 18,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.46),
        foregroundColor: Colors.white,
        fixedSize: Size(size, size),
        minimumSize: Size(size, size),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(size > 44 ? 18 : 12),
        ),
      ),
      icon: Icon(icon, size: iconSize),
    );
  }
}

class _GalleryRow extends StatelessWidget {
  const _GalleryRow({
    required this.saved,
    required this.savedText,
    required this.missingText,
    required this.saveText,
    required this.onSave,
  });

  final bool saved;
  final String savedText;
  final String missingText;
  final String saveText;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: saved ? kBrandTint : kAmberTint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                saved ? LucideIcons.circleCheck : LucideIcons.triangleAlert,
                size: 17,
                color: saved ? kGreen : kAmber,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                saved ? savedText : missingText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        if (!saved)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 42, top: 2),
            child: TextButton.icon(
              onPressed: onSave,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(LucideIcons.save, size: 15),
              label: Text(saveText),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Link details and history
// ---------------------------------------------------------------------------

String _hostOf(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  return host.startsWith('www.') ? host.substring(4) : host;
}

String _bytesLabel(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// A link already sitting on the clipboard. Tapping anywhere uses it; the X
/// only hides the suggestion.
class _ClipboardCard extends StatelessWidget {
  const _ClipboardCard({
    required this.strings,
    required this.url,
    required this.onUse,
    required this.onDismiss,
  });

  final AppLocalizations strings;
  final String url;
  final VoidCallback onUse;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: strings.clipboardUse,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onUse,
        child: SurfaceCard(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
          color: kBrandTint.withValues(alpha: 0.62),
          shadow: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD4E6DA)),
                ),
                child: const Icon(
                  LucideIcons.clipboardPaste,
                  size: 16,
                  color: kGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.clipboardFound,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: kDeepGreen,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _hostOf(url),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: kMuted,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.arrowRight,
                          size: 12,
                          color: kGreen,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            strings.clipboardUse,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: kGreen,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                onPressed: onDismiss,
                tooltip: strings.clipboardNo,
                visualDensity: VisualDensity.compact,
                icon: const Icon(LucideIcons.x, size: 16, color: kMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quality and size, read from the link before anything is downloaded.
class _QualityPicker extends StatelessWidget {
  const _QualityPicker({
    required this.strings,
    required this.probe,
    required this.probing,
    required this.audioOnly,
    required this.maxHeight,
    required this.onChanged,
  });

  final AppLocalizations strings;
  final LinkProbe? probe;
  final bool probing;
  final bool audioOnly;
  final int maxHeight;
  final void Function(bool audioOnly, int maxHeight) onChanged;

  String _duration(int ms) {
    if (ms <= 0) return '';
    final total = (ms / 1000).floor();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = probe;
    if (probing || data == null) {
      return SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        shadow: false,
        color: kSurfaceMuted,
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                strings.checkingLink,
                style: theme.textTheme.bodySmall?.copyWith(color: kMuted),
              ),
            ),
          ],
        ),
      );
    }

    final videos = data.videoOptions;
    final audio = data.audioOption;
    final duration = _duration(data.durationMs);

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  LucideIcons.circleCheck,
                  size: 15,
                  color: kGreen,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  data.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(height: 1.3),
                ),
              ),
              if (duration.isNotEmpty) ...[
                const SizedBox(width: 8),
                MetaPill(icon: LucideIcons.clock, label: duration),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            strings.quality.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: kMuted,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in videos)
                _QualityChip(
                  label: '${option.height}p',
                  size: _bytesLabel(option.sizeBytes),
                  selected: !audioOnly && option.height == maxHeight,
                  onTap: () => onChanged(false, option.height),
                ),
              if (videos.isEmpty && data.unknownVideoOption != null)
                _QualityChip(
                  label: 'MP4',
                  size: _bytesLabel(data.unknownVideoOption!.sizeBytes),
                  selected: !audioOnly && maxHeight == 0,
                  onTap: () => onChanged(false, 0),
                ),
              if (audio != null)
                _QualityChip(
                  label: strings.qualityAudio,
                  size: _bytesLabel(audio.sizeBytes),
                  selected: audioOnly,
                  onTap: () => onChanged(true, 0),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QualityChip extends StatelessWidget {
  const _QualityChip({
    required this.label,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? kBrandTint : kSurfaceMuted,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? kGreen.withValues(alpha: 0.55) : kLine,
              width: selected ? 1.4 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? kDeepGreen : kInk,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (size.isNotEmpty)
                Text(
                  size,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: kMuted,
                    letterSpacing: 0,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the video player when the user asked for sound only.
class _AudioCard extends StatelessWidget {
  const _AudioCard({required this.result, required this.strings});

  final VideoResult result;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      color: kBrandTint.withValues(alpha: 0.6),
      shadow: false,
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD4E6DA)),
            ),
            child: const Icon(
              LucideIcons.music2,
              size: 24,
              color: kGreen,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.audioTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: kDeepGreen,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  strings.audioBody,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: kMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({
    required this.strings,
    required this.items,
    required this.onChanged,
  });

  final AppLocalizations strings;
  final List<HistoryEntry> items;
  final Future<void> Function() onChanged;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  late List<HistoryEntry> _items = List<HistoryEntry>.of(widget.items);
  bool _working = false;

  AppLocalizations get s => widget.strings;

  Future<void> _reload() async {
    await widget.onChanged();
    final items = await HistoryStore.load();
    if (mounted) setState(() => _items = List<HistoryEntry>.of(items));
  }

  Future<void> _clear() async {
    if (_working) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.recentClearTitle),
        content: Text(s.recentClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.clipboardNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.recentClear),
          ),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => _working = true);
    try {
      await HistoryStore.clear();
      await _reload();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _open(HistoryEntry entry) async {
    final uri = entry.uri;
    if (uri == null) return;
    await NativeBridge.openUri(uri, entry.mime);
  }

  Future<void> _share(HistoryEntry entry) async {
    final uri = entry.uri;
    if (uri == null) return;
    final response = await NativeBridge.shareWhatsAppUri(uri, entry.mime);
    if (!mounted) return;
    if (response == 'not_installed') {
      _snack(s.whatsappMissing);
    } else if (response != 'ok') {
      _snack(s.shareFailed);
    }
  }

  Future<void> _delete(HistoryEntry entry) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.deleteTitle),
        content: Text(s.deleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.clipboardNo),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: kRed),
            child: Text(s.deleteFile),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final removed = await NativeBridge.deleteUri(
      uri: entry.uri,
      path: entry.path,
    );
    if (!mounted) return;
    if (!removed) {
      _snack(s.deleteFailed);
      return;
    }
    await HistoryStore.remove(entry.id);
    await _reload();
    if (mounted) _snack(s.fileDeleted);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: kLine, width: 1.0)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F0F1A14),
            blurRadius: 28,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kLineStrong,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 17),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.recent,
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                  SoftIconButton(
                    icon: LucideIcons.x,
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: s.close,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 34),
                  child: Column(
                    children: [
                      const EmptyStateIcon(
                        icon: LucideIcons.history,
                        size: 62,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        s.recentEmptyTitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        s.recentEmptyBody,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: kMuted,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 6),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _row(_items[index]),
                  ),
                ),
              if (_items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton(
                    onPressed: _working ? null : _clear,
                    style: TextButton.styleFrom(
                      foregroundColor: kMuted,
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: Text(s.recentClear),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(HistoryEntry entry) {
    final theme = Theme.of(context);
    final thumbnail = entry.thumbnailPath;
    final date = MaterialLocalizations.of(context)
        .formatShortDate(entry.createdAt.toLocal());
    final detail = [
      if (entry.sizeBytes > 0) _bytesLabel(entry.sizeBytes),
      date,
    ].join('  ·  ');

    return InkWell(
      onTap: () => _open(entry),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: SizedBox(
                width: 52,
                height: 52,
                child: thumbnail != null && File(thumbnail).existsSync()
                    ? Image.file(
                        File(thumbnail),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _thumbFallback(entry),
                      )
                    : _thumbFallback(entry),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(height: 1.3),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: kMuted),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(
                LucideIcons.ellipsisVertical,
                size: 18,
                color: kMuted,
              ),
              onSelected: (value) {
                switch (value) {
                  case 'open':
                    _open(entry);
                  case 'share':
                    _share(entry);
                  case 'delete':
                    _delete(entry);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'open',
                  child: Row(
                    children: [
                      const Icon(LucideIcons.folderOpen, size: 16),
                      const SizedBox(width: 9),
                      Text(s.openFile),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      const Icon(LucideIcons.messageCircle, size: 16),
                      const SizedBox(width: 9),
                      Text(s.sendWhatsApp),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.trash2,
                        size: 16,
                        color: kRed,
                      ),
                      const SizedBox(width: 9),
                      Text(
                        s.deleteFile,
                        style: const TextStyle(color: kRed),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbFallback(HistoryEntry entry) {
    return Container(
      color: entry.isAudio ? kAmberTint : kBrandTint,
      child: Icon(
        entry.isAudio ? LucideIcons.music2 : LucideIcons.film,
        size: 20,
        color: entry.isAudio ? kAmber : kGreen,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status tools
// ---------------------------------------------------------------------------

String _clockText(int ms) {
  if (ms <= 0) return '—';
  final total = (ms / 1000).floor();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// The four one-tap rescues for a clip that WhatsApp would otherwise reject.
class _StatusToolsCard extends StatelessWidget {
  const _StatusToolsCard({
    required this.strings,
    required this.onFit,
    required this.onSplit,
    required this.onTrim,
    required this.onCompress,
    this.fitBlocked,
    this.splitBlocked,
    this.trimBlocked,
    this.compressBlocked,
  });

  final AppLocalizations strings;
  final VoidCallback onFit;
  final VoidCallback onSplit;
  final VoidCallback onTrim;
  final VoidCallback onCompress;

  /// When set, the action would change nothing and the row explains why.
  final String? fitBlocked;
  final String? splitBlocked;
  final String? trimBlocked;
  final String? compressBlocked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EmptyStateIcon(
                icon: LucideIcons.smartphone,
                size: 38,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.statusTools,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      strings.statusToolsHelp,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: kMuted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            LucideIcons.info,
                            size: 12,
                            color: kMuted,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            strings.reencodeNote,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: kMuted,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          _ToolRow(
            icon: LucideIcons.rectangleVertical,
            title: strings.fitStatus,
            help: strings.fitStatusHelp,
            reason: fitBlocked,
            onTap: onFit,
          ),
          const Divider(height: 1),
          _ToolRow(
            icon: LucideIcons.columns2,
            title: strings.splitStatus,
            help: strings.splitStatusHelp,
            reason: splitBlocked,
            onTap: onSplit,
          ),
          const Divider(height: 1),
          _ToolRow(
            icon: LucideIcons.scissors,
            title: strings.trimVideo,
            help: strings.trimVideoHelp,
            reason: trimBlocked,
            onTap: onTrim,
          ),
          const Divider(height: 1),
          _ToolRow(
            icon: LucideIcons.fileDown,
            title: strings.compressVideo,
            help: strings.compressVideoHelp,
            reason: compressBlocked,
            onTap: onCompress,
          ),
        ],
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.icon,
    required this.title,
    required this.help,
    required this.onTap,
    this.reason,
  });

  final IconData icon;
  final String title;
  final String help;
  final String? reason;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = reason == null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: title,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: kSurfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kLine),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: enabled ? kDeepGreen : kMuted,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: enabled ? kInk : kMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reason ?? help,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: kMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (enabled)
                Transform.flip(
                  flipX: Directionality.of(context) == TextDirection.rtl,
                  child: const Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: kMuted,
                  ),
                )
              else
                const Icon(
                  LucideIcons.check,
                  size: 16,
                  color: kGreen,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The list of parts produced by "Split into parts".
class _PartsCard extends StatelessWidget {
  const _PartsCard({
    required this.strings,
    required this.parts,
    required this.selected,
    required this.onSelect,
  });

  final AppLocalizations strings;
  final List<VideoResult> parts;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8, bottom: 4),
            child: Text(
              strings.parts.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: kMuted,
                letterSpacing: 0.9,
              ),
            ),
          ),
          for (var index = 0; index < parts.length; index++)
            _partRow(context, theme, index),
        ],
      ),
    );
  }

  Widget _partRow(BuildContext context, ThemeData theme, int index) {
    final part = parts[index];
    final isSelected = index == selected;
    final detail = [
      _clockText(part.durationMs),
      if (part.sizeBytes > 0) _bytesLabel(part.sizeBytes),
    ].join('  ·  ');

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${strings.parts} ${index + 1}',
      child: InkWell(
        onTap: () => onSelect(index),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? kBrandTint : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: isSelected ? kSurface : kSurfaceMuted,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: kLine),
                ),
                child: Icon(
                  isSelected ? LucideIcons.check : LucideIcons.film,
                  size: 15,
                  color: isSelected ? kGreen : kMuted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${strings.parts} ${index + 1}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: isSelected ? kDeepGreen : kInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: kMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrimDialog extends StatefulWidget {
  const _TrimDialog({
    required this.strings,
    required this.durationMs,
    required this.path,
  });

  final AppLocalizations strings;
  final int durationMs;
  final String path;

  @override
  State<_TrimDialog> createState() => _TrimDialogState();
}

class _TrimDialogState extends State<_TrimDialog> {
  static const double _maxLength = 59.5;

  late final double _max = widget.durationMs / 1000;
  late double _start = 0;
  late double _end = _max < _maxLength ? _max : _maxLength;

  String? _preview;
  bool _previewLoading = false;
  Timer? _previewTimer;
  int _previewMs = -1;

  @override
  void initState() {
    super.initState();
    _schedulePreview(_start);
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    super.dispose();
  }

  void _schedulePreview(double seconds) {
    _previewTimer?.cancel();
    _previewTimer = Timer(
      const Duration(milliseconds: 200),
      () => _loadPreview((seconds * 1000).round()),
    );
  }

  Future<void> _loadPreview(int ms) async {
    if (widget.path.isEmpty) return;
    _previewMs = ms;
    if (mounted) setState(() => _previewLoading = true);
    String? frame;
    try {
      frame = await NativeBridge.frameAt(path: widget.path, timeMs: ms);
    } catch (_) {
      frame = null;
    }
    if (!mounted || _previewMs != ms) return;
    setState(() {
      _preview = frame;
      _previewLoading = false;
    });
  }

  String _clock(double seconds) {
    final total = seconds.round();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.strings;
    return AlertDialog(
      scrollable: true,
      title: Text(s.trimTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.trimHelp,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: kMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Container(
                color: kSurfaceMuted,
                child: _preview != null && File(_preview!).existsSync()
                    ? Image.file(File(_preview!), fit: BoxFit.contain)
                    : Center(
                        child: _previewLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(
                                LucideIcons.film,
                                size: 22,
                                color: kMuted,
                              ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          RangeSlider(
            values: RangeValues(_start, _end),
            min: 0,
            max: _max,
            divisions: (_max * 2).round().clamp(2, 1200),
            labels: RangeLabels(_clock(_start), _clock(_end)),
            onChanged: (values) {
              var start = values.start;
              var end = values.end;
              if (end - start > _maxLength) {
                final movingStart =
                    (start - _start).abs() > (end - _end).abs();
                if (movingStart) {
                  end = start + _maxLength;
                } else {
                  start = end - _maxLength;
                }
              }
              setState(() {
                _start = start;
                _end = end;
              });
              _schedulePreview(start);
            },
          ),
          Row(
            children: [
              Expanded(
                child: _TrimValue(
                  label: s.trimStart,
                  value: _clock(_start),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TrimValue(
                  label: s.trimEnd,
                  value: _clock(_end),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: () {
            final start = (_start * 1000)
                .round()
                .clamp(0, widget.durationMs - 500)
                .toInt();
            var end = (_end * 1000)
                .round()
                .clamp(start + 500, widget.durationMs)
                .toInt();
            if (end - start > 59500) end = start + 59500;
            Navigator.of(context).pop((
              startMs: start,
              endMs: end,
            ));
          },
          child: Text(s.apply),
        ),
      ],
    );
  }
}

class _TrimValue extends StatelessWidget {
  const _TrimValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: kSurfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: kMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _CompressDialog extends StatefulWidget {
  const _CompressDialog({
    required this.strings,
    required this.currentBytes,
    required this.sizeText,
  });

  final AppLocalizations strings;
  final int currentBytes;
  final String sizeText;

  @override
  State<_CompressDialog> createState() => _CompressDialogState();
}

class _CompressDialogState extends State<_CompressDialog> {
  static const _presets = [8, 16, 24];

  late int _megabytes = _initial();

  int _initial() {
    final currentMb = widget.currentBytes / (1024 * 1024);
    var choice = _presets.first;
    for (final mb in _presets) {
      if (mb < currentMb) choice = mb;
    }
    return choice;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.strings;
    return AlertDialog(
      scrollable: true,
      title: Text(s.compressTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.compressHelp,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: kMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mb in _presets)
                ChoiceChip(
                  label: Text('$mb MB'),
                  selected: _megabytes == mb,
                  onSelected: (_) => setState(() => _megabytes = mb),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${s.targetSize}: ${widget.sizeText}',
            style: theme.textTheme.bodySmall?.copyWith(color: kMuted),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_megabytes * 1024 * 1024),
          child: Text(s.apply),
        ),
      ],
    );
  }
}
