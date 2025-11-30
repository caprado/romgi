import 'package:dio/dio.dart';

class ErrorUtils {
  /// Convert an error to a user-friendly message
  static String getUserFriendlyMessage(dynamic error) {
    if (error is DioException) {
      return _getDioErrorMessage(error);
    }

    final errorStr = error.toString().toLowerCase();

    // Check for common error patterns
    if (errorStr.contains('socketexception') ||
        errorStr.contains('connection refused')) {
      return 'Unable to connect to the server. Please check your internet connection.';
    }

    if (errorStr.contains('timeout') || errorStr.contains('timed out')) {
      return 'Connection timed out. The server may be slow or unavailable.';
    }

    if (errorStr.contains('handshake') || errorStr.contains('certificate')) {
      return 'Secure connection failed. Please try again later.';
    }

    // Generic fallback
    return 'Something went wrong. Please try again.';
  }

  static String _getDioErrorMessage(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timed out. The server is taking too long to respond.';
      case DioExceptionType.sendTimeout:
        return 'Request timed out while sending data.';
      case DioExceptionType.receiveTimeout:
        return 'Response timed out. The server is taking too long.';
      case DioExceptionType.badCertificate:
        return 'Secure connection failed. Please try again later.';
      case DioExceptionType.badResponse:
        return _getHttpErrorMessage(error.response?.statusCode);
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      case DioExceptionType.connectionError:
        return 'Unable to connect. Please check your internet connection.';
      case DioExceptionType.unknown:
        // Check the underlying error
        final message = error.message?.toLowerCase() ?? '';
        if (message.contains('socketexception') ||
            message.contains('connection refused') ||
            message.contains('network is unreachable')) {
          return 'Unable to connect. Please check your internet connection.';
        }
        if (message.contains('handshake')) {
          return 'Secure connection failed. Please try again later.';
        }
        return 'Connection failed. Please try again.';
    }
  }

  static String _getHttpErrorMessage(int? statusCode) {
    if (statusCode == null) return 'Server error. Please try again.';

    switch (statusCode) {
      case 400:
        return 'Invalid request. Please try again.';
      case 401:
        return 'Authentication required.';
      case 403:
        return 'Access denied.';
      case 404:
        return 'The requested content was not found.';
      case 429:
        return 'Too many requests. Please wait a moment and try again.';
      case 500:
        return 'Server error. The service is having issues.';
      case 502:
        return 'Server is temporarily unavailable. Please try again later.';
      case 503:
        return 'Service is currently unavailable. Please try again later.';
      case 504:
        return 'Server took too long to respond. Please try again.';
      default:
        if (statusCode >= 500) {
          return 'Server error. Please try again later.';
        }
        return 'Request failed. Please try again.';
    }
  }

  /// Get an appropriate icon for the error type
  static ErrorDisplay getErrorDisplay(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    final isTimeout =
        errorStr.contains('timeout') ||
        errorStr.contains('timed out') ||
        (error is DioException &&
            (error.type == DioExceptionType.connectionTimeout ||
                error.type == DioExceptionType.receiveTimeout ||
                error.type == DioExceptionType.sendTimeout));

    final isConnectionError =
        errorStr.contains('socketexception') ||
        errorStr.contains('connection') ||
        errorStr.contains('network') ||
        (error is DioException &&
            error.type == DioExceptionType.connectionError);

    if (isTimeout) {
      return ErrorDisplay(
        title: 'Connection Timed Out',
        message: getUserFriendlyMessage(error),
        icon: ErrorIcon.timeout,
      );
    }

    if (isConnectionError) {
      return ErrorDisplay(
        title: 'Connection Error',
        message: getUserFriendlyMessage(error),
        icon: ErrorIcon.noConnection,
      );
    }

    if (error is DioException && error.type == DioExceptionType.badResponse) {
      final statusCode = error.response?.statusCode ?? 0;
      if (statusCode >= 500) {
        return ErrorDisplay(
          title: 'Server Error',
          message: getUserFriendlyMessage(error),
          icon: ErrorIcon.server,
        );
      }
    }

    return ErrorDisplay(
      title: 'Error',
      message: getUserFriendlyMessage(error),
      icon: ErrorIcon.generic,
    );
  }
}

enum ErrorIcon { noConnection, timeout, server, generic }

class ErrorDisplay {
  final String title;
  final String message;
  final ErrorIcon icon;

  const ErrorDisplay({
    required this.title,
    required this.message,
    required this.icon,
  });
}
