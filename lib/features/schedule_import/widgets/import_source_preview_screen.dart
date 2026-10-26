import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

class ImportSourcePreviewScreen extends StatefulWidget {
  const ImportSourcePreviewScreen({super.key, required this.path});

  final String path;

  @override
  State<ImportSourcePreviewScreen> createState() =>
      _ImportSourcePreviewScreenState();
}

class _ImportSourcePreviewScreenState extends State<ImportSourcePreviewScreen> {
  late final bool _isPdf = p.extension(widget.path).toLowerCase() == '.pdf';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          p.basename(widget.path),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _isPdf
          ? PdfViewer.file(widget.path)
          : ColoredBox(
              color: scheme.surfaceContainerLow,
              child: Center(
                child: InteractiveViewer(
                  minScale: .5,
                  maxScale: 5,
                  child: Image.file(
                    File(widget.path),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'The original image could not be opened. Return to the import review and try another file.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
