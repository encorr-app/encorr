import 'package:flutter/material.dart';

import '../../theme/encorr_brand.dart';
import '../../theme/mono_tokens.dart';

/// Subtle cinematic light ribbons layered behind content on dark surfaces.
class EncorrAmbientBackground extends StatelessWidget {
  final Widget child;
  final bool enabled;

  const EncorrAmbientBackground({super.key, required this.child, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!enabled || !isDark) return child;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: t.bg),
        const Positioned(left: -120, bottom: -80, child: _GlowOrb(size: 420, gradient: EncorrBrand.ambientRibbonLeft)),
        const Positioned(right: -100, bottom: -60, child: _GlowOrb(size: 380, gradient: EncorrBrand.ambientRibbonRight)),
        child,
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Gradient gradient;

  const _GlowOrb({required this.size, required this.gradient});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
      ),
    );
  }
}
