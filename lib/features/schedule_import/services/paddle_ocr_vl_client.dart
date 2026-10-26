import 'dart:convert';
import 'dart:io';

/// Optional high-accuracy OCR pass against a self-hosted **PaddleOCR-VL-1.6**
/// service (the 0.9B document-parsing vision-language model, state of the art
/// on OmniDocBench v1.6). The model and pipeline are free (Apache-2.0,
/// weights on HuggingFace/ModelScope) but need a GPU-class host, so the app
/// talks to a server the user runs themselves - typically a PC on the same
/// network:
///
/// ```
/// # PaddleOCR repository, deploy/paddleocr_vl_docker/accelerators/nvidia-gpu/
/// docker compose up          # pipeline API on :8080, VLM server behind it
/// # or manually:
/// paddlex --install serving
/// paddlex --serve --pipeline PaddleOCR-VL --port 8080
/// ```
///
/// The client posts the image as base64 JSON ({"file": ..., "fileType": 1})
/// and reads the markdown document parse from the response. Both known
/// serving paths are probed (`/paddleocr-vl`, then `/layout-parsing`) and the
/// first that answers is cached. When no server is configured, or it cannot
/// be reached within the timeout, scanning silently falls back to the fully
/// offline on-device PP-OCRv6 engine bundled with `paddle_ocr_native` - the
/// latest offline-capable OCR available for Flutter.
class PaddleOcrVlClient {
  PaddleOcrVlClient({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 25),
  });

  final String baseUrl;
  final Duration timeout;

  static const List<String> _paths = ['/paddleocr-vl', '/layout-parsing'];

  /// Path of the serving route that answered most recently, so later scans
  /// do not pay the probe cost again.
  static String? _workingPath;

  /// Reads the image and returns its markdown document parse, or null when
  /// the server is unreachable, errors, or returns no usable text.
  Future<String?> parseImage(String filePath) async {
    final root = baseUrl.trim();
    if (root.isEmpty) return null;
    try {
      final bytes = await File(filePath).readAsBytes();
      final body = jsonEncode({
        'file': base64Encode(bytes),
        'fileType': 1,
        'visualize': false,
      });
      final paths = _workingPath == null ? _paths : <String>[_workingPath!];
      for (final path in paths) {
        final markdown = await _post(root, path, body);
        if (markdown == null) continue;
        _workingPath = path;
        return markdown;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _post(String root, String path, String body) async {
    final client = HttpClient();
    client.connectionTimeout = timeout;
    try {
      final uri = Uri.parse(root);
      final request = await client.postUrl(
        uri.replace(
          path: uri.path.endsWith('/')
              ? '${uri.path}${path.substring(1)}'
              : path,
        ),
      );
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final timer = Stopwatch()..start();
      request.write(body);
      final response = await request.close().timeout(timeout);
      final payload = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        final errorCode = decoded['errorCode'];
        if (errorCode is int && errorCode != 0) return null;
      }
      final markdown = _findMarkdown(decoded);
      if (markdown == null || markdown.trim().isEmpty) return null;
      debugLog(
        'VL $path answered in ${timer.elapsedMilliseconds}ms '
        '(${markdown.length} chars)',
      );
      return markdown;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Deep-searches the response envelope for a markdown payload. PaddleX
  /// serving wraps it as result.layoutParsingResults[i].markdown (the
  /// PaddleOCR-VL pipeline mirrors the PP-StructureV3 response shape), but
  /// prunedResult.markdown and ocrResults variants exist across versions.
  static String? _findMarkdown(dynamic node) {
    if (node is String) return null;
    if (node is Map) {
      final direct = node['markdown'];
      if (direct is String && direct.trim().isNotEmpty) return direct;
      for (final value in node.values) {
        final found = _findMarkdown(value);
        if (found != null && found.trim().isNotEmpty) return found;
      }
    }
    if (node is List) {
      for (final value in node) {
        final found = _findMarkdown(value);
        if (found != null && found.trim().isNotEmpty) return found;
      }
    }
    return null;
  }

  /// debugPrint is only in Flutter foundation; keep the client pure Dart.
  static void debugLog(String message) {
    stdout.writeln('[PaddleOcrVl] $message');
  }
}
