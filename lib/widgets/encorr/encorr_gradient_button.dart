import 'package:flutter/material.dart';

import '../../theme/encorr_brand.dart';

/// Primary CTA surface with the Encorr orange-to-magenta gradient and glow.
class EncorrGradientButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  const EncorrGradientButton({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
    this.borderRadius = const BorderRadius.all(Radius.circular(32)),
  });

  @override
  Widget build(BuildContext context) {
    final surface = Container(
      padding: padding,
      decoration: EncorrBrand.gradientSurface(borderRadius: borderRadius),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        child: IconTheme.merge(data: const IconThemeData(color: Colors.white), child: child),
      ),
    );

    if (onTap == null) return surface;

    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: borderRadius, child: surface),
    );
  }
}
