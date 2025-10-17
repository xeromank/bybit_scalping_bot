import 'package:flutter/material.dart';
import 'package:bybit_scalping_bot/constants/theme_constants.dart';
import 'package:bybit_scalping_bot/constants/app_constants.dart';

/// A button widget that shows loading indicator when pressed
///
/// Responsibility: Provide a reusable button with loading state
///
/// This widget encapsulates the common pattern of showing a loading
/// indicator while an async operation is in progress.
class LoadingButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? backgroundColor;
  final Color? textColor;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final ButtonStyle? style;

  const LoadingButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.backgroundColor,
    this.textColor,
    this.width,
    this.height,
    this.padding,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ??
        ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? ThemeConstants.buttonPrimaryColor,
          foregroundColor: textColor ?? ThemeConstants.textOnPrimaryColor,
          padding: padding ??
              const EdgeInsets.symmetric(
                horizontal: ThemeConstants.spacingLarge,
                vertical: ThemeConstants.spacingMedium,
              ),
          minimumSize: Size(
            width ?? double.infinity,
            height ?? AppConstants.buttonHeight,
          ),
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(ThemeConstants.borderRadiusMedium),
          ),
        );

    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: effectiveStyle,
      child: isLoading
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  textColor ?? ThemeConstants.textOnPrimaryColor,
                ),
              ),
            )
          : Text(
              text,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: textColor ?? ThemeConstants.textOnPrimaryColor,
              ),
            ),
    );
  }
}

/// A success-styled button (green)
class SuccessButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  const SuccessButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return LoadingButton(
      text: text,
      onPressed: onPressed,
      isLoading: isLoading,
      backgroundColor: ThemeConstants.buttonSuccessColor,
    );
  }
}

/// A danger-styled button (red)
class DangerButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  const DangerButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return LoadingButton(
      text: text,
      onPressed: onPressed,
      isLoading: isLoading,
      backgroundColor: ThemeConstants.buttonDangerColor,
    );
  }
}
