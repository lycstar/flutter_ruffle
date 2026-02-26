import 'package:flutter/services.dart';
import 'package:ruffle/ruffle.dart';

class SwfSource {
  final String name;
  final String url;
  final Uint8List bytes;
  final String? filePath;

  const SwfSource({
    required this.name,
    required this.url,
    required this.bytes,
    required this.filePath,
  });
}

class SwfInfo {
  final SwfSource source;
  final SwfHeaderInfo header;

  const SwfInfo({
    required this.source,
    required this.header,
  });

  /// SWF 舞台宽度（像素）。
  double get widthPx => header.widthPx;

  /// SWF 舞台高度（像素）。
  double get heightPx => header.heightPx;

  /// SWF 宽高比。
  double get aspectRatio => widthPx <= 0 || heightPx <= 0 ? 1.0 : widthPx / heightPx;
}

