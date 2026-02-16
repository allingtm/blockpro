import 'dart:io';

String getErrorMessage(Object error) {
  if (error is HttpException) return _getHttpErrorMessage(error);

  if (error is Exception) {
    final message = error.toString().toLowerCase();
    if (message.contains('socketexception') || message.contains('network')) {
      return 'Unable to connect. Please check your internet connection.';
    }
    if (message.contains('timeout')) {
      return 'The request timed out. Please try again.';
    }
    if (message.contains('not authenticated') ||
        message.contains('unauthorized')) {
      return 'Your session has expired. Please sign in again.';
    }
    if (message.contains('failed to login')) {
      return 'Failed to login. Please check your email and password.';
    }
    final clean = error.toString().replaceAll('Exception: ', '');
    if (clean.length < 100) return clean;
  }

  return 'Something went wrong. Please try again.';
}

String _getHttpErrorMessage(HttpException error) {
  final msg = error.message.toLowerCase();
  if (msg.contains('401') || msg.contains('unauthorized')) {
    return 'Your session has expired. Please sign in again.';
  }
  if (msg.contains('403') || msg.contains('forbidden')) {
    return 'You do not have permission to perform this action.';
  }
  if (msg.contains('404') || msg.contains('not found')) {
    return 'The requested item was not found.';
  }
  if (msg.contains('500') || msg.contains('server error')) {
    return 'A server error occurred. Please try again later.';
  }
  return 'An error occurred while processing your request.';
}
