import 'dart:io';

import 'package:gangplank/src/lcu_live_game_watcher.dart';
import 'package:gangplank/src/lcu_http_client.dart';
import 'package:gangplank/src/lcu_socket.dart';
import 'package:gangplank/src/lcu_watcher.dart';
import 'package:gangplank/src/storage.dart';

export './src/lcu_watcher.dart' show LCUWatcher, LCUWatcherConfig, LCUCredentials;
export './src/lcu_socket.dart' show LCUSocket, LCUSocketConfig, EventResponse;
export './src/lcu_http_client.dart' show LCUHttpClient, LCUHttpClientConfig, LCUHttpClientException;
export './src/lcu_live_game_watcher.dart' show LCULiveGameWatcher, LCULiveGameWatcherConfig, LCULiveGameWatcherSummary;

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
  
  // SAVE HERE TO PROVIDE DISPOSE METHOD ON GANGPLANK AND TO ASSERT

  LCUWatcher? _watcher;
  LCUSocket? _socket;
  LCUHttpClient? _httpClient;
  LCULiveGameWatcher? _liveGameWatcher;

  /// Init Gangplank, you can disable logging globally for Gangplank by providing [disableLogging].
  Gangplank({ bool disableLogging = false }) {
    _storage = LCUStorage(
      disableLogging: disableLogging,
    );
  }

  /// Initializes an instance of [LCUWatcher] and returns it.
  /// 
  /// Optionally you can provide a [LCUWatcherConfig].
  /// 
  /// Only call this method once and reuse the instance.
  LCUWatcher createLCUWatcher({ LCUWatcherConfig? config }) {
    assert(_watcher == null, 'ONLY INITIALIZE ONE INSTANCE OF LCUWATCHER');

    _watcher = LCUWatcher(
      storage: _storage,
      config: config,
    );

    return _watcher!;
  }

  /// Initializes an instance of [LCUSocket] and returns it.
  /// 
  /// Optionally you can provide a [LCUSocketConfig].
  /// 
  /// Only call this method once and reuse the instance.
  LCUSocket createLCUSocket({ LCUSocketConfig? config }) {
    assert(_socket == null, 'ONLY INITIALIZE ONE INSTANCE OF LCUSOCKET');

    _socket = LCUSocket(
      storage: _storage,
      config: config,
    );

    return _socket!;
  }

  /// Initializes an instance of [LCUHttpClient] and returns it.
  /// 
  /// Optionally you can provide a [LCUHttpClientConfig].
  /// 
  /// Only call this method once and reuse the instance.
  LCUHttpClient createLCUHttpClient({ LCUHttpClientConfig? config }) {
    assert(_httpClient == null, 'ONLY INITIALIZE ONE INSTANCE OF LCUHTTPCLIENT');

    _httpClient = LCUHttpClient(
      storage: _storage,
      config: config,
    );

    return _httpClient!;
  }

  /// Initializes an instance of [LCULiveGameWatcher] and returns it.
  /// 
  /// Optionally you can provide a [LCULiveGameWatcherConfig].
  /// 
  /// Only call this method once and reuse the instance.
  /// 
  /// The [LCULiveGameWatcher] works independently so you can call the watch function at any point.
  LCULiveGameWatcher createLCULiveGameWatcher({ LCULiveGameWatcherConfig? config }) {
    assert(_liveGameWatcher == null, 'ONLY INITIALIZE ONE INSTANCE OF LCULIVEGAMEWATCHER');

    _liveGameWatcher = LCULiveGameWatcher(
      storage: _storage,
      config: config,
    );

    return _liveGameWatcher!;
  }

  /// Disposes [LCUWatcher], [LCUSocket] and [LCULiveGameWatcherConfig] if they were initialized.
  void dispose() {
    _watcher?.dispose();
    _socket?.dispose();
    _liveGameWatcher?.dispose();
  }
}