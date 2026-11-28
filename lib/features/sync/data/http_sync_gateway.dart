import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/entities/sync_change.dart';
import '../domain/entities/sync_record.dart';
import '../domain/repositories/sync_ports.dart';
import 'sync_wire_mapper.dart';

/// The HTTP implementation of [SyncRemoteGateway].
///
/// It owns the base URL, auth header, status handling, and JSON decoding.
/// Domain and application code never see an HTTP type.
class HttpSyncGateway implements SyncRemoteGateway {
  HttpSyncGateway({required this.baseUrl, this.client});

  final String Function() baseUrl;
  final http.Client? client;

  @override
  Future<SyncPushAck> push({
    required String token,
    required SyncPushBatch batch,
  }) async {
    final response = await _post(
      Uri.parse('${baseUrl()}/sync/push'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(SyncWireMapper.pushBody(batch)),
    );
    if (response.statusCode != 200) {
      throw SyncGatewayException(
        'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const SyncGatewayException('Malformed push response.');
    }
    return SyncWireMapper.parsePushAck(data);
  }

  @override
  Future<SyncPullBatch> pull({
    required String token,
    required String deviceId,
    required DateTime? since,
  }) async {
    final sinceText =
        since?.toUtc().toIso8601String() ?? '1970-01-01T00:00:00.000Z';
    final response = await _get(
      Uri.parse(
        '${baseUrl()}/sync/pull?since=$sinceText'
        '&device_id=${Uri.encodeQueryComponent(deviceId)}',
      ),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw SyncGatewayException(
        'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const SyncGatewayException('Malformed pull response.');
    }
    return SyncWireMapper.parsePullBatch(data);
  }

  Future<http.Response> _post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) {
    final httpClient = client;
    return httpClient != null
        ? httpClient.post(uri, headers: headers, body: body)
        : http.post(uri, headers: headers, body: body);
  }

  Future<http.Response> _get(Uri uri, {required Map<String, String> headers}) {
    final httpClient = client;
    return httpClient != null
        ? httpClient.get(uri, headers: headers)
        : http.get(uri, headers: headers);
  }
}
