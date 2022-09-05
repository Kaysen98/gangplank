import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gangplank/src/logging.dart';
import 'package:gangplank/src/storage.dart';

class LCUCredentials {
  final String host, username, password;
  final int port;
  final File lockfile;
  final Directory leagueDir;

  LCUCredentials({
    this.host = '127.0.0.1',
    required this.port,
    this.username = 'riot',
    required this.password,
    required this.lockfile,
    required this.leagueDir,
  });

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'username': username,
    'password': password,
    'lockfilePath': lockfile.path,
    'leagueDir': leagueDir.path,
  };

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

class LCUWatcher {
  late final GangplankLogger _logger;
  late final LCUStorage _storage;

  static const _commandWin = "WMIC PROCESS WHERE name='LeagueClientUx.exe' GET commandline";
  final _regexWin = RegExp(r'--install-directory=(.*?)"');

  static const _commandMAC = "ps x -o args | grep 'LeagueClientUx'";
  final _regexMAC = RegExp(r'/--install-directory=(.*?)( --|\n|$)/');

  bool _clientIsRunning = false;

  final StreamController<LCUCredentials> _onClientStartedStreamController = StreamController.broadcast();
  final StreamController<void> _onClientClosedStreamController = StreamController.broadcast();

  Stream<LCUCredentials> get onClientStarted => _onClientStartedStreamController.stream;
  Stream<void> get onClientClosed => _onClientClosedStreamController.stream;
  bool get clientIsRunning => _clientIsRunning;

  Timer? _timerProcessWatcher;
  StreamSubscription? _lockfileWatcher;

  LCUWatcher({required LCUStorage storage}) {
    _storage = storage;

    _logger = GangplankLogger(
      service: 'LCU-WATCHER',
      storage: _storage,
    );
  }

  /// The LCUWatcher will watch for the League client presence.
  /// 
  /// If the LCUWatcher finds the running League client the [onClientStarted] event will be fired.
  /// 
  /// If League client is closed the [onClientClosed] event will be fired.
  void watch() {
    _checkForProcess();

    _logger.log('STARTED');
  }

  /// Stop watching the League client.
  /// 
  /// This will also clean up the currently saved [LCUCredentials].
  /// That results in the LCUSocket and LCUHttpClient to stop working until the [onClientStarted] event is fired again.
  void stopWatching() {
    _timerProcessWatcher?.cancel();
    _lockfileWatcher?.cancel();
    _clientIsRunning = false;
    _onClientClosedStreamController.add(null);
    _storage.credentials = null;

    _logger.log('STOPPED');
  }

  Future<void> _checkForProcess() async {
    _logger.log('WAITING TO FIND THE LCU PROCESS');

    await _searchLockfilePath();

    if (!clientIsRunning) {
      // LOCK FILE WAS NOT FOUND, START INTERVALL TO CHECK FOR PROCESS

      _timerProcessWatcher = Timer.periodic(const Duration(seconds: 5), (_) {
        _searchLockfilePath();
      });
    }
  }

  void _initFileWatcher() {
    // WE DO NOT NEED TO SAVE THE SUBSCRIPTION AND CANCEL IT MANUALLY
    // WHEN THE FILE IS DELETED THE WATCHER IS DISPOSED AUTOMATICALLY
    // WE ONLY NEED IT TO CANCEL THE SUBSCRIPTION IN CASE THE USER STOPS THE WATCHER

    _lockfileWatcher = _storage.credentials!.leagueDir.watch(
      events: FileSystemEvent.delete,
    ).listen((event) {
      if (event.path == _storage.credentials?.lockfile.path) {
        // LOCKFILE WAS TOUCHED

        if (event.type == FileSystemEvent.delete) {
          _clientIsRunning = false;
          _onClientClosedStreamController.add(null);
          _storage.credentials = null;
          _lockfileWatcher!.cancel();

          _logger.log('DISCONNECTED! LOCKFILE DELETED');

          _checkForProcess();
        }
      }
    });

    _logger.log('WATCHING LOCKFILE NOW');
  }

  Future<void> _searchLockfilePath() async {
    String? path = await _getLCUPathFromProcess();

    if (path != null) {
      // THE PROCESS IS RUNNING -> PATH COULD BE EXTRACTED FROM PROCESS

      File lockfile = File('$path\\lockfile');

      if (await lockfile.exists()) {
        String fileContent = await lockfile.readAsString();
        List<String> splitData = fileContent.split(':');

        _storage.credentials = LCUCredentials(
          port: int.parse(splitData[2]),
          password: splitData[3],
          lockfile: lockfile,
          leagueDir: Directory(path),
        );

        _timerProcessWatcher?.cancel();
        
        _clientIsRunning = true;
        _onClientStartedStreamController.add(_storage.credentials!);

        _logger.log('CONNECTED! PROCESS FOUND');
        _logger.log(_storage.credentials.toString());

        _initFileWatcher();
      }
    }
  }

  Future<String?> _getLCUPathFromProcess() async {
    if (Platform.isWindows) {
      final result = await Process.run(
        _commandWin,
        [],
        runInShell: true,
      );

      final match = _regexWin.firstMatch(result.stdout);
      final matchedText = match?.group(1);

      return matchedText;
    } else if (Platform.isMacOS) {
      final result = await Process.run(
        _commandMAC,
        [],
        runInShell: true,
      );

      final match = _regexMAC.firstMatch(result.stdout);
      final matchedText = match?.group(1);

      return matchedText;
    }

    return null;
  }

  /// Call dispose to clean all subscriptions when you are finished using the LCUWatcher.
  dispose() {
    stopWatching();
    _timerProcessWatcher?.cancel();
    _lockfileWatcher?.cancel();
    _onClientStartedStreamController.close();
    _onClientClosedStreamController.close();
  }
}