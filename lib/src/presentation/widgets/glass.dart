import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Static gradients provide most of the depth. Blur is opt-in and clipped to
/// small floating surfaces; scrolling cards never allocate backdrop filters.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 26,
    this.frosted = false,
    this.tint,
    this.onTap,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool frosted;
  final Color? tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    final surface = Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: shape,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: .94),
              (tint ?? const Color(0xFFF3FAF5)).withValues(alpha: .87),
            ],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: .95),
            width: 1.2,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: JeepLinkColors.green.withValues(alpha: .065),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: frosted && !MediaQuery.disableAnimationsOf(context)
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: surface,
              )
            : surface,
      ),
    );
  }
}

class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFECF7EE), Color(0xFFF9F8F1), Color(0xFFE7F3EE)],
      ),
    ),
    child: Stack(
      children: [
        const Positioned(
          top: -100,
          right: -100,
          width: 330,
          height: 460,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0x667CDAB4), Color(0x007CDAB4)],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    ),
  );
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => GlassPanel(
    radius: 17,
    padding: EdgeInsets.zero,
    child: IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, color: JeepLinkColors.ink),
    ),
  );
}

/// Short entrance, no repeated animation and no motion under accessibility mode.
class SoftEntrance extends StatelessWidget {
  const SoftEntrance({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 7),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
