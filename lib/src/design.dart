import 'package:flutter/material.dart';
import 'package:lucide_icons_lite/lucide_icons_lite.dart';

import 'theme.dart';

// ---------------------------------------------------------------------------
// Page Chrome & Canvas
// ---------------------------------------------------------------------------

/// A serene, quiet studio canvas behind every screen.
/// Free of random flashy neon glows or template gradients.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kCanvasTop, kCanvasBottom],
        ),
      ),
      child: child,
    );
  }
}

/// Responsive frame with disciplined gutters and comfortable tablet reading width.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.child,
    this.padding,
    this.maxWidth = 540,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 360 ? 16.0 : 20.0;
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: padding ??
              EdgeInsets.fromLTRB(horizontal, 10, horizontal, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Surfaces & Content Cards
// ---------------------------------------------------------------------------

/// Precision-crafted surface card with hairline borders and soft ambient diffusion.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = kSurface,
    this.radius = 20,
    this.borderColor = kLine,
    this.gradient,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  final Color borderColor;
  final Gradient? gradient;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: const Color(0xFF0F1A14).withValues(alpha: 0.038),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: const Color(0xFF0F1A14).withValues(alpha: 0.02),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    this.eyebrow,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = EdgeInsets.zero,
  });

  final String? eyebrow;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!.toUpperCase(),
                    style: textTheme.labelSmall?.copyWith(
                      color: kGreen,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 5),
                ],
                Text(title, style: textTheme.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: textTheme.bodySmall?.copyWith(
                      color: kMuted,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: kMuted,
                  letterSpacing: 1.15,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Brand Identity Mark
// ---------------------------------------------------------------------------

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 46});

  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.28;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E7C55), Color(0xFF0C4D32)],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: const Color(0xFF2FA273).withValues(alpha: 0.35),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A442B).withValues(alpha: 0.22),
            blurRadius: size * 0.35,
            offset: Offset(0, size * 0.14),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          LucideIcons.arrowDownToLine,
          color: Colors.white,
          size: size * 0.48,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Interactive Controls
// ---------------------------------------------------------------------------

class SoftIconButton extends StatelessWidget {
  const SoftIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 42,
    this.tint = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final bool tint;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final background = tint ? kBrandTint : kSurface;
    final foreground = enabled ? (tint ? kDeepGreen : kInk) : kMuted;
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF111915).withValues(alpha: 0.035),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: kLine, width: 1.0),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: Icon(icon, size: size * 0.46, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}

enum DepthTone { primary, secondary, whatsapp, danger, quiet }

/// A true 3D mechanical push button with realistic keycap tactile depth.
/// Physically translates down under the finger with an authentic compressed edge.
class DepthButton extends StatefulWidget {
  const DepthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = DepthTone.primary,
    this.expand = true,
    this.busy = false,
    this.minHeight = 54,
    this.trailing,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final DepthTone tone;
  final bool expand;
  final bool busy;
  final double minHeight;
  final Widget? trailing;

  @override
  State<DepthButton> createState() => _DepthButtonState();
}

class _DepthButtonState extends State<DepthButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.busy;

  void _setPressed(bool value) {
    if (!mounted || !_enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  _ButtonPalette get _palette {
    switch (widget.tone) {
      case DepthTone.primary:
        return const _ButtonPalette(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF22875D), Color(0xFF105F3E)],
          ),
          foreground: Colors.white,
          edge: Color(0xFF083A25),
          shadow: Color(0xFF105F3E),
        );
      case DepthTone.secondary:
        return const _ButtonPalette(
          background: kSurface,
          foreground: kInk,
          edge: Color(0xFFCBD5E1),
          border: kLineStrong,
          shadow: Color(0xFF94A3B8),
        );
      case DepthTone.whatsapp:
        return const _ButtonPalette(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2CD96C), Color(0xFF1BA652)],
          ),
          foreground: Colors.white,
          edge: Color(0xFF0E6B34),
          shadow: Color(0xFF1BA652),
        );
      case DepthTone.danger:
        return const _ButtonPalette(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE04C40), Color(0xFFB52E23)],
          ),
          foreground: Colors.white,
          edge: Color(0xFF7A1C14),
          shadow: Color(0xFFB52E23),
        );
      case DepthTone.quiet:
        return const _ButtonPalette(
          background: kSurfaceMuted,
          foreground: kInk,
          edge: Color(0xFFD6DFD9),
          border: kLine,
          shadow: Color(0xFF94A3B8),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    final enabled = _enabled;
    const edgeDepth = 4.0;
    final currentEdge = _pressed ? 1.0 : edgeDepth;

    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.busy)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: palette.foreground,
            ),
          )
        else if (widget.icon != null)
          Icon(
            widget.icon,
            size: 19,
            color: enabled ? palette.foreground : palette.foreground.withValues(alpha: 0.45),
          ),
        if (widget.busy || widget.icon != null) const SizedBox(width: 9),
        Flexible(
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: kFontBody,
              fontFamilyFallback: kFontFallback,
              fontSize: 15,
              height: 1.25,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
              color: enabled ? palette.foreground : palette.foreground.withValues(alpha: 0.45),
            ),
          ),
        ),
        if (widget.trailing != null) ...[
          const SizedBox(width: 8),
          widget.trailing!,
        ],
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapUp: enabled ? (_) => _setPressed(false) : null,
          onTapCancel: enabled ? () => _setPressed(false) : null,
          onTap: enabled ? widget.onPressed : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 75),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(0, _pressed ? 3.0 : 0, 0),
            constraints: BoxConstraints(minHeight: widget.minHeight),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              color: palette.background,
              gradient: palette.gradient,
              borderRadius: BorderRadius.circular(16),
              border: palette.border == null
                  ? null
                  : Border.all(color: palette.border!, width: 1.0),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: palette.edge,
                        offset: Offset(0, currentEdge),
                        blurRadius: 0,
                      ),
                      BoxShadow(
                        color: palette.shadow.withValues(alpha: _pressed ? 0.08 : 0.18),
                        offset: Offset(0, _pressed ? 2 : 6),
                        blurRadius: _pressed ? 6 : 14,
                      ),
                    ]
                  : null,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _ButtonPalette {
  const _ButtonPalette({
    this.background,
    this.gradient,
    required this.foreground,
    required this.edge,
    this.border,
    required this.shadow,
  });

  final Color? background;
  final Gradient? gradient;
  final Color foreground;
  final Color edge;
  final Color? border;
  final Color shadow;
}

// ---------------------------------------------------------------------------
// Metadata Pills & Banners
// ---------------------------------------------------------------------------

class MetaPill extends StatelessWidget {
  const MetaPill({
    super.key,
    required this.icon,
    required this.label,
    this.foreground = kInk,
    this.background = kSurfaceSofter,
    this.borderColor = kLine,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13.5, color: foreground),
          const SizedBox(width: 5.5),
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: kFontBody,
                fontFamilyFallback: kFontFallback,
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NoteBanner extends StatelessWidget {
  const NoteBanner({
    super.key,
    required this.icon,
    required this.text,
    this.foreground = kDeepGreen,
    this.background = kBrandTint,
    this.borderColor = const Color(0xFFD4E6DA),
    this.trailing,
  });

  final IconData icon;
  final String text;
  final Color foreground;
  final Color background;
  final Color borderColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16.5, color: foreground),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: kFontBody,
                fontFamilyFallback: kFontFallback,
                fontSize: 12.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: foreground,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class EmptyStateIcon extends StatelessWidget {
  const EmptyStateIcon({
    super.key,
    required this.icon,
    this.color = kGreen,
    this.background = kBrandTint,
    this.size = 64,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * 0.30),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1.0),
      ),
      child: Icon(icon, color: color, size: size * 0.46),
    );
  }
}
