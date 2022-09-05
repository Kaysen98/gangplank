import 'dart:io';

import 'package:gangplank/src/lcu_http_client.dart';
import 'package:gangplank/src/lcu_socket.dart';
import 'package:gangplank/src/lcu_watcher.dart';
import 'package:gangplank/src/storage.dart';

export './src/lcu_watcher.dart' show LCUCredentials;
export './src/lcu_socket.dart' show EventResponse;

class GangplankHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

class Gangplank {
  late LCUStorage _storage;
  late LCUWatcher watcher;
  late LCUSocket socket;
  late LCUHttpClient httpClient;

  Gangplank({ bool disableLogging = false }) {
    _storage = LCUStorage();

    _storage.disableLogging = disableLogging;
    
    watcher = LCUWatcher(storage: _storage);
    socket = LCUSocket(storage: _storage);
    httpClient = LCUHttpClient(storage: _storage);
  }

  dispose() {
    watcher.dispose();
    socket.dispose();
  }
}