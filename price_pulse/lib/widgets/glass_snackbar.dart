import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum SnackBarType {
  success, // Green dot - product added, restored, etc.
  error, // Red dot - errors, failures
  warning, // Orange dot - warnings
  info, // Blue dot - information
  celebration, // Green dot - bought, congratulations
  delete, // Red dot - delete actions
}

class GlassSnackBar extends StatelessWidget {
  final String message;
  final SnackBarType type;
  final Duration duration;
  final Widget? action;
  final IconData? icon;

  const GlassSnackBar({
    Key? key,
    required this.message,
    required this.type,
    this.duration = const Duration(seconds: 3),
    this.action,
    this.icon,
  }) : super(key: key);

  Color _getDotColor() {
    switch (type) {
      case SnackBarType.success:
      case SnackBarType.celebration:
        return AppTheme.accentGreen;
      case SnackBarType.error:
      case SnackBarType.delete:
        return AppTheme.accentRed;
      case SnackBarType.warning:
        return AppTheme.accentOrange;
      case SnackBarType.info:
        return AppTheme.accentBlue;
    }
  }

  IconData _getDefaultIcon() {
    if (icon != null) return icon!;
    switch (type) {
      case SnackBarType.success:
        return Icons.check_circle_rounded;
      case SnackBarType.error:
      case SnackBarType.delete:
        return Icons.error_outline_rounded;
      case SnackBarType.warning:
        return Icons.warning_rounded;
      case SnackBarType.info:
        return Icons.info_outline_rounded;
      case SnackBarType.celebration:
        return Icons.celebration_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), // Thicker than product cards (16px)
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.4),
                width: 2,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFE8E8E8).withOpacity(0.85), // White smoke color
                  const Color(0xFFD0D0D0).withOpacity(0.80), // Slightly darker smoke
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 15,
                  spreadRadius: 0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Colored dot indicator
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _getDotColor(),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _getDotColor().withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Icon
                Icon(
                  _getDefaultIcon(),
                  color: Colors.black87,
                  size: 22,
                ),
                const SizedBox(width: 12),
                // Message
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                // Action button (if provided)
                if (action != null) ...[
                  const SizedBox(width: 12),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void show(
    BuildContext context, {
    required String message,
    required SnackBarType type,
    Duration duration = const Duration(seconds: 3),
    Widget? action,
    IconData? icon,
  }) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: GlassSnackBar(
          message: message,
          type: type,
          duration: duration,
          action: action,
          icon: icon,
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        margin: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: bottomPadding + 8, // Position at bottom, FAB will automatically move up
        ),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

