import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Saves generated SoilSense files directly to the phone's public Downloads
/// collection on Android. This intentionally avoids the Android share sheet.
class FileDownloadService {
  static const MethodChannel _channel = MethodChannel('soilsense/file_download');

  static Future<String> savePdf({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final result = await _channel.invokeMethod<String>(
      'savePdfToDownloads',
      <String, dynamic>{
        'bytes': bytes,
        'fileName': fileName,
      },
    );
    if (result == null || result.trim().isEmpty) {
      throw StateError('Android did not return a saved file location.');
    }
    return result;
  }
}
