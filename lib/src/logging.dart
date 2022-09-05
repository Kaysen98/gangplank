import 'package:flutter/foundation.dart';
import 'package:gangplank/src/storage.dart';

class GangplankLogger {
  String service;
  LCUStorage storage;

  GangplankLogger({required this.service, required this.storage});

  log(String message) {
    if (kDebugMode && !LCUStorage().disableLogging)
      print('GANGPLANK - $service: $message');
  }
}
