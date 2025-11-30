import 'package:flutter/material.dart';

import '../utils/error_utils.dart';

class ErrorView extends StatelessWidget {
  final dynamic error;
  final VoidCallback? onRetry;
  final bool compact;

  const ErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final errorDisplay = ErrorUtils.getErrorDisplay(error);
    final theme = Theme.of(context);

    if (compact) {
      return _buildCompactView(context, errorDisplay, theme);
    }

    return _buildFullView(context, errorDisplay, theme);
  }

  Widget _buildFullView(
    BuildContext context,
    ErrorDisplay errorDisplay,
    ThemeData theme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildIcon(errorDisplay.icon, theme, size: 64),
            const SizedBox(height: 24),
            Text(
              errorDisplay.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              errorDisplay.message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompactView(
    BuildContext context,
    ErrorDisplay errorDisplay,
    ThemeData theme,
  ) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _buildIcon(errorDisplay.icon, theme, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    errorDisplay.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    errorDisplay.message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (onRetry != null)
              IconButton(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                tooltip: 'Try again',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(ErrorIcon icon, ThemeData theme, {required double size}) {
    final color = theme.colorScheme.error;

    switch (icon) {
      case ErrorIcon.noConnection:
        return Icon(Icons.wifi_off_rounded, size: size, color: color);
      case ErrorIcon.timeout:
        return Icon(Icons.hourglass_empty_rounded, size: size, color: color);
      case ErrorIcon.server:
        return Icon(Icons.cloud_off_rounded, size: size, color: color);
      case ErrorIcon.generic:
        return Icon(Icons.error_outline_rounded, size: size, color: color);
    }
  }
}

class SliverErrorView extends StatelessWidget {
  final dynamic error;
  final VoidCallback? onRetry;

  const SliverErrorView({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      child: ErrorView(error: error, onRetry: onRetry),
    );
  }
}
