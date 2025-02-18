class ZKErrorConnection implements Exception {
  final String message;
  ZKErrorConnection(this.message);

  @override
  String toString() => 'ZKErrorConnection: $message';
}

class ZKNetworkError implements Exception {
  final String message;
  ZKNetworkError(this.message);

  @override
  String toString() => 'ZKNetworkError: $message';
}
