import '../domain/repositories/sync_ports.dart';

/// Keeps the controller's error strings stable while the transport moves
/// behind a port.
String syncFailureMessage(String operation, SyncGatewayException error) =>
    error.statusCode != null
    ? '$operation failed: ${error.statusCode}'
    : '$operation error: ${error.message}';
