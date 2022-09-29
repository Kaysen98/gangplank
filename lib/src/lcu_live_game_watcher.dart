import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gangplank/src/logging.dart';
import 'package:gangplank/src/storage.dart';
import 'package:http/http.dart';

enum GamePresenceCheckStrategy { process, http }

class LCULiveGameWatcherConfig {
  /// Disables the logging for the [LCULiveGameWatcher].
  ///
  /// [disableLogging] defaults to `false`.
  final bool disableLogging;

  /// The interval used to check whether there is an active League of Legends game.
  ///
  /// [gamePresenceCheckerInterval] defaults to 10 seconds.
  final Duration gamePresenceCheckerInterval;

  /// The interval used send an updated game summary via stream.
  ///
  /// [gameSummaryInterval] defaults to 5 seconds.
  final Duration gameSummaryInterval;

  /// The [GamePresenceCheckStrategy] used to check for the gameclient's presence.
  ///
  /// The HTTP strategy will force the watcher to do a HTTP request to check for game presence.
  /// If the request fails it will be catched, indicating the game is not present at the moment.
  ///
  /// The process strategy will force the watcher to check via process (cmd) to check for game presence.
  ///
  /// It's encouraged to use `GamePresenceCheckStrategy.process` over `GamePresenceCheckStrategy.http`.
  ///
  /// [GamePresenceCheckStrategy] defaults to `GamePresenceCheckStrategy.process`.
  final GamePresenceCheckStrategy gamePresenceCheckStrategy;

  /// Whether to fetch the playerlist and put it into the summary.
  ///
  /// If you set it to `false` the summaries playerList property will always be an empty list.
  ///
  /// [fetchPlayerList] defaults to `true`.
  final bool fetchPlayerList;

  /// Whether to emit `null` on the game summary update stream when the game ended.
  ///
  /// [emitNullForGameSummaryUpdateOnGameEnded] defaults to `true`.
  final bool emitNullForGameSummaryUpdateOnGameEnded;

  /// Whether to emit `0` on the game timer update stream when the game ended.
  ///
  /// [emitResettedGameTimerOnGameEnded] defaults to `true`.
  final bool emitResettedGameTimerOnGameEnded;

  LCULiveGameWatcherConfig({
    this.disableLogging = false,
    this.gamePresenceCheckerInterval = const Duration(seconds: 10),
    this.gameSummaryInterval = const Duration(seconds: 5),
    this.gamePresenceCheckStrategy = GamePresenceCheckStrategy.process,
    this.fetchPlayerList = true,
    this.emitNullForGameSummaryUpdateOnGameEnded = true,
    this.emitResettedGameTimerOnGameEnded = true,
  })  : assert(gamePresenceCheckerInterval.inSeconds >= 1, 'THE GAME PRESENCE CHECKER INTERVAL MUST BE ONE SECOND OR GREATER'),
        assert(gameSummaryInterval.inSeconds >= 1, 'THE GAME SUMMARY INTERVAL MUST BE ONE SECOND OR GREATER');
}

class LCULiveGameWatcherSummary {
  dynamic gameStats;
  List<dynamic> eventData, playerList;

  LCULiveGameWatcherSummary({required this.gameStats, required this.eventData, required this.playerList});

  Map<String, dynamic> toJson() => {
        'gameStats': gameStats,
        'eventData': eventData,
        'playerList': playerList,
      };

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

class LCULiveGameWatcher {
  late final GangplankLogger _logger;
  late final LCUStorage _storage;

  // CONFIG

  late final LCULiveGameWatcherConfig _config;

  static const _commandWin = "WMIC PROCESS WHERE name='League of Legends.exe' GET commandline";
  final _regexWin = RegExp(r'-RiotClientPort=(.*?)"');

  static const _commandMAC = 'ps';
  static const _commandArgsMAC = ["aux", "-o", "args | grep 'League of Legends'"];
  final _regexMAC = RegExp(r'-RiotClientPort=(.*?)( -|\n|$)');

  static const _timeout = Duration(seconds: 3);

  final StreamController _onGameFoundStreamController = StreamController.broadcast();
  final StreamController _onGameEndedStreamController = StreamController.broadcast();
  final StreamController<int> _onGameStartedStreamController = StreamController.broadcast();
  final StreamController<LCULiveGameWatcherSummary?> _onGameSummaryUpdateStreamController = StreamController.broadcast();
  final StreamController<int> _onGameTimerUpdateStreamController = StreamController.broadcast();

  /// [onGameFound] emits one event when an active game was found.
  Stream get onGameFound => _onGameFoundStreamController.stream;

  /// [onGameEnded] emits one event when an active game has ended.
  Stream get onGameEnded => _onGameEndedStreamController.stream;

  /// [onGameStarted] emits one event when an active game has started and the summoners can interact with the game.
  Stream<int> get onGameStarted => _onGameStartedStreamController.stream;

  /// [onGameSummaryUpdate] emits on the given interval of [LCULiveGameWatcherConfig] and emits a summary of the game data.
  Stream<LCULiveGameWatcherSummary?> get onGameSummaryUpdate => _onGameSummaryUpdateStreamController.stream;

  /// [onGameTimerUpdate] emits an event every second after [onGameStarted] emitted once.
  /// This can be used to show a timer in your app.
  /// Use the [formatSecondsToMMSS] method to format from seconds format to MM:SS format.
  Stream<int> get onGameTimerUpdate => _onGameTimerUpdateStreamController.stream;

  bool gameInProgress = false;
  bool gameHasStarted = false;

  Timer? _gamePresenceWatcherTimer;
  Timer? _gameWatcherTimer;
  Timer? _gameTimerUpdateTimer;

  int _internalGameTime = 0;

  LCULiveGameWatcher({required LCUStorage storage, LCULiveGameWatcherConfig? config}) {
    _storage = storage;

    _config = config ?? LCULiveGameWatcherConfig();

    _logger = GangplankLogger(
      service: 'LCU-LIVE-GAME-WATCHER',
      storage: _storage,
    );

    if (!_config.disableLogging) _logger.log('USING ${_config.gamePresenceCheckStrategy == GamePresenceCheckStrategy.process ? 'PROCESS' : 'HTTP'} STRATEGY');
  }

  /// The LCULiveClientWatcher will watch for the League gameclient presence.
  ///
  /// If the LCULiveClientWatcher finds an ongoing game the [onGameFound] event will be fired.
  ///
  /// If the gameclient is closed and/or terminated the [onGameEnded] event will be fired.
  ///
  /// If the game itself has started the [onGameStarted] event will be fired.
  ///
  /// If there is a summary update the [onGameSummaryUpdate] event will be fired.
  ///
  /// If the game itself has started and the timer is updated the [onGameTimerUpdate] event will be fired.
  void watch() {
    _checkForGamePresence();

    _gamePresenceWatcherTimer = Timer.periodic(_config.gamePresenceCheckerInterval, (timer) async {
      await _checkForGamePresence();
    });

    if (!_config.disableLogging) _logger.log('WATCHING');
  }

  /// Stop watching the League gameclient.
  void stopWatching() {
    _gamePresenceWatcherTimer?.cancel();
    _gameWatcherTimer?.cancel();
    _gameTimerUpdateTimer?.cancel();
    gameInProgress = false;
    gameHasStarted = false;
    _internalGameTime = 0;

    if (!_config.disableLogging) _logger.log('STOPPED WATCHING');
  }

  Future<bool> _isGamePresent() async {
    if (_config.gamePresenceCheckStrategy == GamePresenceCheckStrategy.process) {
      if (Platform.isWindows) {
        final result = await Process.run(
          _commandWin,
          [],
          runInShell: true,
        );

        final match = _regexWin.firstMatch(result.stdout);
        final matchedText = match?.group(1);

        return matchedText != null;
      } else if (Platform.isMacOS) {
        final result = await Process.run(_commandMAC, _commandArgsMAC);

        final match = _regexMAC.firstMatch(result.stdout);
        final matchedText = match?.group(1);

        return matchedText != null;
      }
    } else if (_config.gamePresenceCheckStrategy == GamePresenceCheckStrategy.http) {
      try {
        await get(Uri.parse('${_storage.gameClientApi}gamestats')).timeout(_timeout);
        return true;
      } catch (err) {}
    }

    return false;
  }

  Future _checkForGamePresence() async {
    if (await _isGamePresent()) {
      if (!gameInProgress) {
        gameInProgress = true;

        _startGameWatcherInterval();

        _onGameFoundStreamController.add(null);

        if (!_config.disableLogging) _logger.log('GAME FOUND');
      }
    } else {
      if (gameInProgress) {
        gameInProgress = false;
        gameHasStarted = false;

        // GAME ENDED -> KILL GAME WATCHER
        _killGameWatcherInterval();
        _killGameTimerUpdateInterval();

        _onGameEndedStreamController.add(null);

        if (!_config.disableLogging) _logger.log('GAME ENDED');
      }
    }
  }

  Future _startGameWatcherInterval() async {
    final summary = await getGameSummary();

    if (summary != null) {
      _onGameSummaryUpdateStreamController.add(summary);

      if (!gameHasStarted && summary.eventData.firstWhere((e) => e['EventName'] == 'GameStart', orElse: () => null) != null) {
        gameHasStarted = true;

        double gt = summary.gameStats['gameTime'];
        int gameTime = gt.ceil();

        _internalGameTime = gameTime;

        _onGameStartedStreamController.add(gameTime);

        _startGameTimerUpdateInterval();

        if (!_config.disableLogging) _logger.log('GAME HAS STARTED');
      }
    }

    _gameWatcherTimer = Timer.periodic(_config.gameSummaryInterval, (_) async {
      final summary = await getGameSummary();

      if (summary != null) {
        _onGameSummaryUpdateStreamController.add(summary);

        if (!gameHasStarted && summary.eventData.firstWhere((e) => e['EventName'] == 'GameStart', orElse: () => null) != null) {
          gameHasStarted = true;

          double gt = summary.gameStats['gameTime'];
          int gameTime = gt.ceil();

          _internalGameTime = gameTime;

          _onGameStartedStreamController.add(gameTime);

          _startGameTimerUpdateInterval();

          if (!_config.disableLogging) _logger.log('GAME HAS STARTED');
        }
      }
    });
  }

  void _killGameWatcherInterval() {
    if (_config.emitNullForGameSummaryUpdateOnGameEnded) _onGameSummaryUpdateStreamController.add(null);

    _gameWatcherTimer?.cancel();
  }

  Future<LCULiveGameWatcherSummary?> getGameSummary() async {
    try {
      final futures = [_requestGameStats(), _requestEventData()];

      futures.add(_config.fetchPlayerList ? _requestPlayerList() : Future.value([]));

      final result = await Future.wait(futures);

      LCULiveGameWatcherSummary summary = LCULiveGameWatcherSummary(
        gameStats: result[0],
        eventData: result[1],
        playerList: result[2],
      );

      return summary;
    } catch (err) {
      if (!_config.disableLogging) _logger.err('NOT ABLE TO RETRIEVE GAME SUMMARY', err);
    }

    return null;
  }

  Future _requestGameStats() async {
    Response result = await get(Uri.parse('${_storage.gameClientApi}gamestats')).timeout(_timeout);
    final stats = jsonDecode(utf8.decode(result.bodyBytes));
    return stats;
  }

  Future _requestEventData() async {
    Response result = await get(Uri.parse('${_storage.gameClientApi}eventdata')).timeout(_timeout);

    final body = jsonDecode(utf8.decode(result.bodyBytes));

    if (body is Map) {
      if (body.containsKey('Events')) {
        final eventData = body['Events'] as List;
        return eventData;
      }
    }

    return [];
  }

  Future _requestPlayerList() async {
    Response result = await get(Uri.parse('${_storage.gameClientApi}playerlist')).timeout(_timeout);
    final playerList = jsonDecode(utf8.decode(result.bodyBytes));

    if (playerList is List) return playerList;

    return [];
  }

  void _startGameTimerUpdateInterval() {
    _gameTimerUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _internalGameTime++;
      _onGameTimerUpdateStreamController.add(_internalGameTime);
    });
  }

  void _killGameTimerUpdateInterval() {
    _gameTimerUpdateTimer?.cancel();
    _internalGameTime = 0;

    if (_config.emitResettedGameTimerOnGameEnded) _onGameTimerUpdateStreamController.add(_internalGameTime);
  }

  String formatSecondsToMMSS(int? time) {
    if (time == null) {
      return '--:--';
    }

    var minutes = (time / 60).floor();
    var seconds = (time - minutes * 60);

    String minutesString = minutes.toString().padLeft(2, '0');
    String secondsString = seconds.toString().padLeft(2, '0');

    return '$minutesString:$secondsString';
  }

  void dispose() {
    _gamePresenceWatcherTimer?.cancel();
    _gameWatcherTimer?.cancel();
    _gameTimerUpdateTimer?.cancel();

    _onGameFoundStreamController.close();
    _onGameEndedStreamController.close();
    _onGameStartedStreamController.close();
    _onGameSummaryUpdateStreamController.close();
    _onGameTimerUpdateStreamController.close();
  }
}
