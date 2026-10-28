import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_lite/lucide_icons_lite.dart';
import 'package:video_player/video_player.dart';

import 'design.dart';
import 'i18n.dart';
import 'models.dart';
import 'native.dart';
import 'settings_sheet.dart';
import 'theme.dart';

enum Phase { booting, idle, preparing, downloading, result, error, engineError }

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.strings,
    required this.language,
    required this.onLanguageChanged,
  });

  final Strings strings;
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

  Strings get s => widget.strings;
  bool get _busy => _phase == Phase.preparing || _phase == Phase.downloading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _events = NativeBridge.events.listen(_onEvent);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _events?.cancel();
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
    if (state == AppLifecycleState.resumed) return;
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
        _snack(s.t('busy'));
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
    });
    _screen(false);
    await _startVideo(result);
    if (_pendingUrl != null) {
      _pendingUrl = null;
    }
  }

  void _onError(DownloadEvent event) {
    if (!mounted) return;
    setState(() {
      _phase = Phase.error;
      _errorCode = event.code ?? 'generic';
      _errorMessage = event.message;
      _errorDetail = event.detail;
      _progress = 0;
      _showDetails = false;
    });
    _screen(false);
  }

  void _onCancelled() {
    if (!mounted) return;
    setState(() {
      _phase = Phase.idle;
      _requestId = null;
      _progress = 0;
      _stage = 'preparing';
      _cancelling = false;
    });
    _screen(false);
  }

  // ---------------------------------------------------------------------
  // Download
  // ---------------------------------------------------------------------

  Future<void> _startDownload(String rawUrl) async {
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
      });
      _urlFocus.unfocus();

      try {
        _screen(true);
        await NativeBridge.download(url: url, requestId: requestId);
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

  Future<void> _cancelDownload() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(s.t('cancelTitle')),
          content: Text(s.t('cancelBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(s.t('keepDownloading')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: kRed,
                minimumSize: const Size(100, 48),
              ),
              child: Text(s.t('stop')),
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
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(s.t('cancelTitle')),
          content: Text(s.t('cancelBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(s.t('keepDownloading')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: kRed,
                minimumSize: const Size(100, 48),
              ),
              child: Text(s.t('stop')),
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
        _snack(s.t('err_no_link'));
        return;
      }
      _urlController.text = url;
      setState(() => _inputError = false);
    } catch (_) {
      _snack(s.t('err_no_link'));
    }
  }

  void _submit() {
    final url = _extractUrl(_urlController.text);
    if (url == null) {
      setState(() => _inputError = true);
      _urlFocus.requestFocus();
      return;
    }
    setState(() => _inputError = false);
    _startDownload(url);
  }

  Future<void> _shareWhatsApp() async {
    final result = _result;
    if (result == null) return;
    try {
      final response = await NativeBridge.shareWhatsApp(result.path);
      if (!mounted) return;
      if (response == 'not_installed') {
        _snack(s.t('whatsappMissing'));
      } else if (response != 'ok') {
        _snack(s.t('shareFailed'));
      }
    } catch (_) {
      if (mounted) _snack(s.t('shareFailed'));
    }
  }

  Future<void> _shareStatus() async {
    final result = _result;
    if (result == null) return;
    try {
      final response = await NativeBridge.shareStatus(result.path);
      if (!mounted) return;
      if (response == 'chat') {
        _snack(s.t('statusFallback'));
      } else if (response == 'not_installed') {
        _snack(s.t('whatsappMissing'));
      } else if (response != 'ok') {
        _snack(s.t('shareFailed'));
      }
    } catch (_) {
      if (mounted) _snack(s.t('shareFailed'));
    }
  }

  Future<void> _shareSystem() async {
    final result = _result;
    if (result == null) return;
    try {
      final response = await NativeBridge.shareSystem(result.path);
      if (!mounted) return;
      if (response != 'ok') _snack(s.t('shareFailed'));
    } catch (_) {
      if (mounted) _snack(s.t('shareFailed'));
    }
  }

  Future<void> _saveAgain() async {
    final result = _result;
    if (result == null) return;
    try {
      final saved = await NativeBridge.saveToGallery(result.path);
      if (!mounted) return;
      setState(() => _gallerySaved = saved);
      if (!saved) _snack(s.t('galleryPermission'));
    } catch (_) {
      if (mounted) _snack(s.t('galleryPermission'));
    }
  }

  Future<void> _shareLink() async {
    final url = _lastUrl;
    if (url == null) return;
    try {
      final response = await NativeBridge.shareText(url);
      if (!mounted) return;
      if (response != 'ok') _snack(s.t('shareFailed'));
    } catch (_) {
      if (mounted) _snack(s.t('shareFailed'));
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
            onLanguageChanged: widget.onLanguageChanged,
          );
        },
      );
    } catch (_) {
      // The sheet is optional; never let it take down the screen.
    }
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

    final bare = direct ??
        RegExp(
          r"""(?:https?://)?(?:www\.|m\.|web\.)?(?:instagram\.com|instagr\.am|ig\.me|facebook\.com|fb\.watch|fb\.com|youtube\.com|youtu\.be|youtube-nocookie\.com|tiktok\.com|vm\.tiktok\.com|twitter\.com|x\.com|threads\.net)/[^\s<>"']+""",
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
    final code = _errorCode ?? 'generic';
    final key = 'err_$code';
    final localized = s.t(key);
    if (localized != key) return localized;
    if (_errorMessage != null && _errorMessage!.trim().isNotEmpty) {
      return _errorMessage!;
    }
    return s.t('err_generic');
  }

  String _etaText(int seconds) {
    if (seconds <= 0) return '';
    final m = seconds ~/ 60;
    final sec = seconds % 60;
    final value = m > 0 ? '$m:${sec.toString().padLeft(2, '0')}' : '${sec}s';
    return s.t('timeLeft').replaceAll('{time}', value);
  }

  String _durationText(int ms) {
    if (ms <= 0) return '—';
    final total = (ms / 1000).floor();
    final m = total ~/ 60;
    final sec = total % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  String _sizeText(int bytes) {
    if (bytes <= 0) return '—';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

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
                s.t('appName'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineLarge,
              ),
              const SizedBox(height: 7),
              Text(
                s.t('appSubtitle'),
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
                s.t(_firstRun ? 'preparingFirst' : 'preparing'),
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
                          s.t('firstTime'),
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
          _AppHeader(strings: s, onSettings: _openSettings),
          const SizedBox(height: 26),
          Text(
            s.t('heroEyebrow').toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: kGreen,
              letterSpacing: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(s.t('tagline'), style: theme.textTheme.displaySmall),
          const SizedBox(height: 10),
          Text(
            s.t('taglineSub'),
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
                label: s.t('trustPrivate'),
                background: kSurface.withValues(alpha: 0.85),
              ),
              MetaPill(
                icon: LucideIcons.shieldCheck,
                label: s.t('trustNoAccount'),
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
          const SizedBox(height: 13),
          Text(
            s.t('worksWith'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: kMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 28),
          SectionHeading(
            title: s.t('howItWorks'),
            subtitle: s.t('howItWorksHelp'),
          ),
          const SizedBox(height: 12),
          _StepsCard(
            step1Title: s.t('step1Title'),
            step1Body: s.t('step1Body'),
            step2Title: s.t('step2Title'),
            step2Body: s.t('step2Body'),
            step3Title: s.t('step3Title'),
            step3Body: s.t('step3Body'),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloading() {
    final theme = Theme.of(context);
    final preparing = _phase == Phase.preparing;
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
                        s.t('progressEyebrow').toUpperCase(),
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
                        preparing ? s.t('preparing') : s.t('statusNote'),
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
                  text: s.t('progressHelp'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DepthButton(
            tone: DepthTone.secondary,
            icon: LucideIcons.x,
            label: s.t('cancel'),
            busy: _cancelling,
            onPressed: _cancelling ? null : _cancelDownload,
          ),
          const SizedBox(height: 4),
          Text(
            s.t('statusNote'),
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
                    MetaPill(
                      icon: result.hasAudio
                          ? LucideIcons.volume2
                          : LucideIcons.volumeX,
                      label: result.hasAudio ? s.t('sound') : s.t('noSound'),
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
                    text: s.t('trimmedNote'),
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
                  savedText: s.t('savedGallery'),
                  missingText: s.t('notSavedGallery'),
                  saveText: s.t('saveGallery'),
                  onSave: _saveAgain,
                ),
              ],
            ),
          ),
          const SizedBox(height: 23),
          SectionHeading(
            title: s.t('sendSection'),
            subtitle: s.t('sendHelp'),
          ),
          const SizedBox(height: 12),
          DepthButton(
            tone: DepthTone.whatsapp,
            icon: LucideIcons.messageCircle,
            label: s.t('sendWhatsApp'),
            onPressed: _shareWhatsApp,
          ),
          const SizedBox(height: 10),
          DepthButton(
            tone: DepthTone.secondary,
            icon: LucideIcons.circlePlus,
            label: s.t('sendStatus'),
            onPressed: _shareStatus,
          ),
          const SizedBox(height: 10),
          DepthButton(
            tone: DepthTone.quiet,
            icon: LucideIcons.share2,
            label: s.t('moreApps'),
            onPressed: _shareSystem,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _done,
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: kMuted,
            ),
            child: Text(s.t('done')),
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
              tooltip: s.t('done'),
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
            s.t('errorTitle'),
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
              label: s.t('loginCookies'),
              onPressed: _openSettings,
            ),
            const SizedBox(height: 10),
          ],
          if (hasLink) ...[
            DepthButton(
              icon: LucideIcons.refreshCw,
              label: s.t('tryAgain'),
              onPressed: _retry,
            ),
            const SizedBox(height: 10),
            DepthButton(
              tone: DepthTone.secondary,
              icon: LucideIcons.share2,
              label: s.t('shareLink'),
              onPressed: _shareLink,
            ),
            const SizedBox(height: 10),
          ],
          DepthButton(
            tone: DepthTone.quiet,
            icon: LucideIcons.settings,
            label: s.t('openSettings'),
            onPressed: _openSettings,
          ),
          const SizedBox(height: 2),
          TextButton(
            onPressed: _done,
            style: TextButton.styleFrom(foregroundColor: kMuted),
            child: Text(s.t('done')),
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
                  _showDetails ? s.t('hideDetails') : s.t('details'),
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
              tooltip: s.t('done'),
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
            s.t('engineErrorTitle'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          Text(
            s.t('engineErrorBody'),
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
            label: s.t('retrySetup'),
            onPressed: _retrySetup,
          ),
          const SizedBox(height: 2),
          TextButton(
            onPressed: _done,
            style: TextButton.styleFrom(foregroundColor: kMuted),
            child: Text(s.t('done')),
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
  const _AppHeader({required this.strings, this.onSettings});

  final Strings strings;
  final VoidCallback? onSettings;

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
                strings.t('appName'),
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
                strings.t('appSubtitle'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: kMuted),
              ),
            ],
          ),
        ),
        if (onSettings != null) ...[
          const SizedBox(width: 8),
          SoftIconButton(
            icon: LucideIcons.settings,
            onPressed: onSettings,
            tooltip: strings.t('settings'),
          ),
        ],
      ],
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.strings, required this.onClose});

  final Strings strings;
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
                strings.t('readyTitle'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                strings.t('readySubtitle'),
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
          tooltip: strings.t('done'),
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

  final Strings strings;
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
                      strings.t('linkLabel'),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      strings.t('linkHelp'),
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
                          strings.t('paste'),
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
            decoration: InputDecoration(
              hintText: strings.t('pasteHint'),
              prefixIcon: const Icon(LucideIcons.link2, size: 17),
              errorText: inputError ? strings.t('err_no_link') : null,
            ),
          ),
          const SizedBox(height: 12),
          DepthButton(
            icon: LucideIcons.arrowDownToLine,
            label: strings.t('download'),
            onPressed: onSubmit,
          ),
          const SizedBox(height: 3),
          Text(
            strings.t('downloadHint'),
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
  final Strings strings;

  @override
  Widget build(BuildContext context) {
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
                              muted ? strings.t('unmute') : strings.t('mute'),
                          onPressed: onToggleMute,
                        ),
                      ),
                      if (paused)
                        Center(
                          child: _VideoControl(
                            icon: LucideIcons.play,
                            tooltip: strings.t('play'),
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
                            tooltip: strings.t('pause'),
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
            padding: const EdgeInsets.only(left: 42, top: 2),
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
