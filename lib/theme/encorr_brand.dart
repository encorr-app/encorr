import 'package:flutter/material.dart';

/// Encorr brand palette and reusable visual primitives inspired by the ticket
/// logo: deep black canvas, orange-to-magenta gradients, and purple glow.
abstract final class EncorrBrand {
  static const Color orange = Color(0xFFFF7A2E);
  static const Color red = Color(0xFFFF3D5C);
  static const Color magenta = Color(0xFFE8328A);
  static const Color purple = Color(0xFF7C3AED);
  static const Color indigo = Color(0xFF4C1D95);

  static const Color darkBg = Color(0xFF06060A);
  static const Color darkSurface = Color(0xFF12101A);
  static const Color oledBg = Color(0xFF000000);
  static const Color oledSurface = Color(0xFF0A0810);

  static const Color lightBg = Color(0xFFF8F7FA);
  static const Color lightSurface = Color(0xFFFFFFFF);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [orange, red, magenta],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [orange, magenta, purple],
  );

  static const LinearGradient ambientRibbonLeft = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [Color(0x664C1D95), Color(0x337C3AED), Color(0x00E8328A)],
  );

  static const LinearGradient ambientRibbonRight = LinearGradient(
    begin: Alignment.bottomRight,
    end: Alignment.topLeft,
    colors: [Color(0x66FF7A2E), Color(0x33FF3D5C), Color(0x00E8328A)],
  );

  static BoxDecoration gradientSurface({BorderRadius? borderRadius, List<BoxShadow>? boxShadow}) {
    return BoxDecoration(
      gradient: primaryGradient,
      borderRadius: borderRadius ?? BorderRadius.circular(999),
      boxShadow: boxShadow ?? accentGlowShadows(),
    );
  }

  static List<BoxShadow> accentGlowShadows({double opacity = 0.35}) {
    return [
      BoxShadow(color: orange.withValues(alpha: opacity * 0.55), blurRadius: 18, spreadRadius: 0),
      BoxShadow(color: magenta.withValues(alpha: opacity * 0.45), blurRadius: 28, spreadRadius: 1),
    ];
  }
}
