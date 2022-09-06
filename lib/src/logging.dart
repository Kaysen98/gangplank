import 'package:flutter/foundation.dart';
import 'package:gangplank/src/storage.dart';

class GangplankLogger {
  String service;
  LCUStorage storage;

  GangplankLogger({required this.service, required this.storage});

  /// Prints a log message in normal color.
  log(String message) {
    if (kDebugMode && !storage.disableLogging) {
      print('GANGPLANK - $service: $message');
    }
  }

  /// Prints an error message in red color.
  err(String message, Object err) {
    if (kDebugMode && !storage.disableLogging) {
      final text = 'GANGPLANK - $service - ERROR: $message';
      print('\x1B[31m$text\x1B[0m');
      print(err.toString());
    }
  }
}
