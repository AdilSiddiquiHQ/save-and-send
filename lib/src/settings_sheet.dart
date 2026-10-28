import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_lite/lucide_icons_lite.dart';

import 'design.dart';
import 'i18n.dart';
import 'native.dart';
import 'theme.dart';
import 'version.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.strings,
    required this.language,
    required this.busy,
    required this.diagnosticUrl,
    required this.onLanguageChanged,
  });

  final AppLocalizations strings;
  final String language;
  final bool busy;
  final String? diagnosticUrl;
  final ValueChanged<String> onLanguageChanged;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  String? _version;
  bool _hasCookies = false;
  bool _loading = true;
  bool _updating = false;
  String? _notice;
  String _channel = 'nightly';
  bool _wifiOnly = false;

  AppLocalizations get s => widget.strings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final version = await NativeBridge.engineVersion();
      final cookies = await NativeBridge.hasCookies();
      final channel = await NativeBridge.getPref('engine_channel');
      final wifiOnly = await NativeBridge.getPref('wifi_only');
      if (!mounted) return;
      setState(() {
        _version = version;
        _hasCookies = cookies;
        _channel = channel == 'stable' ? 'stable' : 'nightly';
        _wifiOnly = wifiOnly == '1';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _update() async {
    if (_updating || widget.busy) return;
    setState(() => _updating = true);
    try {
      final result = await NativeBridge.updateEngine();
      final version = result['version'] as String?;
      if (!mounted) return;
      setState(() {
        _version = version ?? _version;
        _updating = false;
      });
      _message(s.updateDone);
    } catch (_) {
      if (!mounted) return;
      setState(() => _updating = false);
      _message(s.updateFailed);
    }
  }

  Future<void> _setChannel(String value) async {
    if (widget.busy || value == _channel) return;
    setState(() => _channel = value);
    try {
      await NativeBridge.setPref('engine_channel', value);
    } catch (_) {
      _message(s.saveFailed);
    }
  }

  Future<void> _setWifiOnly(bool value) async {
    setState(() => _wifiOnly = value);
    try {
      await NativeBridge.setPref('wifi_only', value ? '1' : '0');
    } catch (_) {
      if (mounted) setState(() => _wifiOnly = !value);
      _message(s.saveFailed);
    }
  }

  Future<void> _diagnose() async {
    final url = widget.diagnosticUrl;
    if (url == null) {
      _message(s.diagnosticsNoLink);
      return;
    }
    await showDiagnosticsDialog(context, s, url);
  }

  Future<void> _editCookies() async {
    final result = await showDialog<String?>(
      context: context,
      builder: (_) {
        return _CookiesDialog(
          strings: s,
          hasCookies: _hasCookies,
        );
      },
    );
    if (!mounted || result == null) return;

    final text = result.trim();
    try {
      final ok = await NativeBridge.setCookies(text.isEmpty ? null : result);
      if (!mounted) return;
      setState(() => _hasCookies = text.isNotEmpty && ok);
      if (text.isEmpty) {
        _message(s.cookiesRemoved);
      } else if (ok) {
        _message(s.cookiesSaved);
      } else {
        _message(s.saveFailed);
      }
    } catch (_) {
      if (mounted) _message(s.saveFailed);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    setState(() => _notice = text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
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
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.settings,
                            style: theme.textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            s.settingsSubtitle,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: kMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SoftIconButton(
                      icon: LucideIcons.x,
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: s.close,
                    ),
                  ],
                ),
                if (_notice != null) ...[
                  const SizedBox(height: 16),
                  NoteBanner(
                    icon: LucideIcons.info,
                    text: _notice!,
                  ),
                ],
                const SizedBox(height: 24),

                SectionLabel(s.language),
                const SizedBox(height: 8),
                _LanguagePicker(
                  value: widget.language,
                  onChanged: (lang) {
                    widget.onLanguageChanged(lang);
                    Navigator.of(context).pop();
                  },
                ),
                const SizedBox(height: 7),
                Text(
                  s.languageHelp,
                  style: theme.textTheme.bodySmall?.copyWith(color: kMuted),
                ),

                const SizedBox(height: 24),
                SectionLabel(s.downloader),
                const SizedBox(height: 8),
                SurfaceCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SettingsIcon(
                            icon: LucideIcons.refreshCw,
                            color: kGreen,
                            background: kBrandTint,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.engineUpdates,
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  s.downloaderHelp,
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: kMuted, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: kSurfaceMuted,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                s.version,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: kMuted),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _loading ? '…' : (_version ?? '—'),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: kDeepGreen,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        s.engineChannel,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        s.engineChannelHelp,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: kMuted, height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      _ChannelPicker(
                        value: _channel,
                        stableLabel: s.engineStable,
                        nightlyLabel: s.engineNightly,
                        onChanged: widget.busy ? null : _setChannel,
                      ),
                      const SizedBox(height: 12),
                      DepthButton(
                        tone: DepthTone.secondary,
                        icon: LucideIcons.refreshCw,
                        label: _updating ? s.updating : s.update,
                        busy: _updating,
                        onPressed: _loading || widget.busy ? null : _update,
                        minHeight: 52,
                      ),
                      if (widget.busy) ...[
                        const SizedBox(height: 8),
                        Text(
                          s.busy,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: kMuted, height: 1.4),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                SurfaceCard(
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                  child: Row(
                    children: [
                      const _SettingsIcon(
                        icon: LucideIcons.wifi,
                        color: kGreen,
                        background: kBrandTint,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.wifiOnly,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              s.wifiOnlyHelp,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: kMuted, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Switch(
                        value: _wifiOnly,
                        onChanged: _setWifiOnly,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                SectionLabel(s.loginCookies),
                const SizedBox(height: 8),
                SurfaceCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SettingsIcon(
                            icon: LucideIcons.keyRound,
                            color: kAmber,
                            background: kAmberTint,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              _hasCookies
                                  ? s.cookiesAdded
                                  : s.cookiesNotAdded,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: _hasCookies ? kGreen : kLineStrong,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.cookiesHelp,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: kMuted, height: 1.5),
                      ),
                      const SizedBox(height: 13),
                      DepthButton(
                        tone: DepthTone.secondary,
                        icon: LucideIcons.squarePen,
                        label: s.addReplace,
                        onPressed: _editCookies,
                        minHeight: 50,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                SectionLabel(s.diagnostics),
                const SizedBox(height: 8),
                SurfaceCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SettingsIcon(
                            icon: LucideIcons.stethoscope,
                            color: kAmber,
                            background: kAmberTint,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              s.diagnosticsHelp,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: kMuted, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DepthButton(
                        tone: DepthTone.secondary,
                        icon: LucideIcons.stethoscope,
                        label: s.diagnosticsRun,
                        onPressed:
                            widget.diagnosticUrl == null ? null : _diagnose,
                        minHeight: 50,
                      ),
                      if (widget.diagnosticUrl == null) ...[
                        const SizedBox(height: 8),
                        Text(
                          s.diagnosticsNoLink,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: kMuted, height: 1.4),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                SectionLabel(s.howTo),
                const SizedBox(height: 8),
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 5,
                  ),
                  child: Column(
                    children: [
                      _MiniStep(number: '01', text: s.step1Body),
                      const Divider(),
                      _MiniStep(number: '02', text: s.step2Body),
                      const Divider(),
                      _MiniStep(number: '03', text: s.step3Body),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                SectionLabel(s.about),
                const SizedBox(height: 8),
                Text(
                  s.aboutBody,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: kMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    const BrandMark(size: 22),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        '${s.personalNote}  •  v$kAppVersion',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: kMuted,
                          letterSpacing: 0.15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                DepthButton(
                  icon: LucideIcons.check,
                  label: s.close,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({
    required this.icon,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: kSurfaceMuted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLine),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final language in AppLanguage.all)
            _LanguageOption(
              label: language.label,
              selected: value == language.code,
              onTap: () => onChanged(language.code),
            ),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: selected ? kSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? kLine : Colors.transparent,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF17221B).withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          // `Align` with `widthFactor: 1` centres the label inside the 46 px
          // chip without making the chip grow to the full row width.
          child: Align(
            alignment: Alignment.center,
            widthFactor: 1,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? kDeepGreen : kMuted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniStep extends StatelessWidget {
  const _MiniStep({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kBrandTint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              number,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: kDeepGreen,
                    letterSpacing: 0,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: kMuted,
                    height: 1.45,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CookiesDialog extends StatefulWidget {
  const _CookiesDialog({
    required this.strings,
    required this.hasCookies,
  });

  final AppLocalizations strings;
  final bool hasCookies;

  @override
  State<_CookiesDialog> createState() => _CookiesDialogState();
}

class _CookiesDialogState extends State<_CookiesDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      titlePadding: const EdgeInsets.fromLTRB(22, 21, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(22, 13, 22, 4),
      actionsPadding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      title: Row(
        children: [
          const _SettingsIcon(
            icon: LucideIcons.keyRound,
            color: kAmber,
            background: kAmberTint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.loginCookies,
              style: theme.textTheme.headlineSmall,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.cookiesHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: kMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            maxLines: 6,
            minLines: 5,
            autocorrect: false,
            enableSuggestions: false,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              height: 1.4,
            ),
            decoration: const InputDecoration(
              hintText:
                  '# Netscape HTTP Cookie File\n.instagram.com\tTRUE\t/\tTRUE\t...',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.cancel),
        ),
        if (widget.hasCookies)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(
              s.remove,
              style: const TextStyle(color: kRed),
            ),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(s.save),
        ),
      ],
    );
  }
}

/// Stable or nightly yt-dlp, as a two-part switch.
class _ChannelPicker extends StatelessWidget {
  const _ChannelPicker({
    required this.value,
    required this.stableLabel,
    required this.nightlyLabel,
    required this.onChanged,
  });

  final String value;
  final String stableLabel;
  final String nightlyLabel;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: kSurfaceMuted,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: kLine),
      ),
      child: Row(
        children: [
          _option(context, 'stable', stableLabel),
          const SizedBox(width: 4),
          _option(context, 'nightly', nightlyLabel),
        ],
      ),
    );
  }

  Widget _option(BuildContext context, String code, String label) {
    final selected = value == code;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(code),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? kSurface : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? kLine : Colors.transparent,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF17221B).withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? kDeepGreen : kMuted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Runs a redacted yt-dlp trace and lets the user copy it.
Future<void> showDiagnosticsDialog(
  BuildContext context,
  AppLocalizations strings,
  String url,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DiagnosticsDialog(strings: strings, url: url),
  );
}

class _DiagnosticsDialog extends StatefulWidget {
  const _DiagnosticsDialog({required this.strings, required this.url});

  final AppLocalizations strings;
  final String url;

  @override
  State<_DiagnosticsDialog> createState() => _DiagnosticsDialogState();
}

class _DiagnosticsDialogState extends State<_DiagnosticsDialog> {
  bool _running = true;
  bool _copied = false;
  String _log = '';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    String log;
    try {
      log = await NativeBridge.diagnose(widget.url);
    } catch (e) {
      log = e.toString();
    }
    if (!mounted) return;
    setState(() {
      _log = log;
      _running = false;
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _log));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      title: Row(
        children: [
          const _SettingsIcon(
            icon: LucideIcons.stethoscope,
            color: kAmber,
            background: kAmberTint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(s.diagnostics, style: theme.textTheme.headlineSmall),
          ),
        ],
      ),
      content: _running
          ? Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.diagnosticsRunning,
                    style: theme.textTheme.bodyMedium?.copyWith(color: kMuted),
                  ),
                ),
              ],
            )
          : Container(
              width: double.maxFinite,
              constraints: const BoxConstraints(maxHeight: 320),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kSurfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kLine),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _log,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.45,
                    color: kMuted,
                  ),
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.close),
        ),
        if (!_running)
          FilledButton.icon(
            onPressed: _copied ? null : _copy,
            icon: Icon(_copied ? LucideIcons.check : LucideIcons.copy, size: 16),
            label: Text(_copied ? s.diagnosticsCopied : s.diagnosticsCopy),
          ),
      ],
    );
  }
}
