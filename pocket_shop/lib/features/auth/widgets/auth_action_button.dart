import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class AuthActionButton extends StatelessWidget {
  const AuthActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.isLoading,
    this.loadingLabel,
    this.height = 46,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final String? loadingLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryCyan,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.darkCyan,
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading
            ? _LoadingLabel(text: loadingLabel ?? 'Please wait...')
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

class _LoadingLabel extends StatefulWidget {
  const _LoadingLabel({required this.text});

  final String text;

  @override
  State<_LoadingLabel> createState() => _LoadingLabelState();
}

class _LoadingLabelState extends State<_LoadingLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final slide = (_controller.value * 2) - 1;
            return ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) {
                return LinearGradient(
                  begin: Alignment(-1 + slide, 0),
                  end: Alignment(1 + slide, 0),
                  colors: const [Colors.white70, Colors.white, Colors.white70],
                  stops: const [0.2, 0.5, 0.8],
                ).createShader(bounds);
              },
              child: child,
            );
          },
          child: Text(
            widget.text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}
