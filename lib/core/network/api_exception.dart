/// Thrown by [ApiClient] for any non-2xx response. [message] is the
/// backend's own error text when it sent one (Nest's default exception
/// filter shape is `{statusCode, message, error}`, and `message` is
/// sometimes an array from class-validator) — callers surface this
/// directly instead of a generic "something went wrong", so a specific
/// rejection (e.g. "Could not verify bank account details with Paystack")
/// reaches the user unchanged.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode, $message)';
}
