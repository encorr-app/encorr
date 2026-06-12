import 'dart:ui';

import 'package:flutter/material.dart';

import '../../services/device_performance.dart';
import '../../services/settings_service.dart';
import '../../theme/mono_tokens.dart';

/// Frosted-glass surface: backdrop blur + translucent fill + 1px hairline
/// border, rounded with [borderRadius].
///
/// On the reduced performance tier ([DevicePerformance.isReduced]) or when the
/// user disables [SettingsService.glassEffects], the panel degrades to a
/// semi-opaque solid container with no [BackdropFilter] — cheap enough for
/// low-end Android TV boxes. [forceFallback] overrides the automatic choice
/// (`true` always uses the cheap path, `false` always blurs).
class GlassPanel extends StatelessWidget {
  final Widget? child;

  /// Corner radius. Defaults to `BorderRadius.circular(tokens.radiusMd)`.
  final BorderRadius? borderRadius;

  /// Inner padding around [child].
  final EdgeInsetsGeometry? padding;

  /// 0–1 multiplier on the glass fill opacity (1 = token default).
  final double tintStrength;

  /// Whether to draw the hairline border.
  final bool border;

  /// `true` forces the cheap solid path, `false` forces the blur path,
  /// `null` (default) decides from settings and the performance tier.
  final bool? forceFallback;

  const GlassPanel({
    super.key,
    this.child,
    this.borderRadius,
    this.padding,
    this.tintStrength = 1.0,
    this.border = true,
    this.forceFallback,
  });

  bool _useFallback(bool glassEnabled) => forceFallback ?? (!glassEnabled || DevicePerformance.isReduced);

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instanceOrNull;
    if (settings == null) {
      // Pre-init (rare): use the cheap path rather than guessing.
      return _buildPanel(context, useFallback: _useFallback(false));
    }
    return ValueListenableBuilder<bool>(
      valueListenable: settings.listenable(SettingsService.glassEffects),
      builder: (context, glassEnabled, _) => _buildPanel(context, useFallback: _useFallback(glassEnabled)),
    );
  }

  Widget _buildPanel(BuildContext context, {required bool useFallback}) {
    final t = tokens(context);
    final radius = borderRadius ?? BorderRadius.circular(t.radiusMd);

    final fill = useFallback
        // Semi-opaque solid stand-in: blends the glass tint onto the surface
        // color so legibility holds without any blur behind it.
        ? Color.alphaBlend(t.glassSurface, t.surface.withValues(alpha: 0.9))
        : t.glassSurface.withValues(alpha: (t.glassSurface.a * tintStrength).clamp(0.0, 1.0));

    // The hairline is drawn as a foreground decoration so it takes no layout
    // space: Container would otherwise add the border width to its padding,
    // silently shrinking the child's box by 2px.
    final panel = Container(
      padding: padding,
      decoration: BoxDecoration(color: fill, borderRadius: radius),
      foregroundDecoration: border
          ? BoxDecoration(borderRadius: radius, border: Border.all(color: t.glassBorder, width: 1))
          : null,
      child: child,
    );

    if (useFallback) return panel;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: t.glassBlurSigma, sigmaY: t.glassBlurSigma),
        child: panel,
      ),
    );
  }
}
