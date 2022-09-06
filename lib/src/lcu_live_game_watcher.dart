import 'dart:async';
import 'dart:convert';

import 'package:gangplank/src/logging.dart';
import 'package:gangplank/src/storage.dart';
import 'package:http/http.dart';
import 'package:collection/collection.dart';

class LCULiveGameWatcherConfig {
  /// Disables the logging for the [LCULiveGameWatcher].
  /// 
  /// [disableLogging] defaults to `false`.
  final bool disableLogging;

  /// The interval used to check wether there is an active League of Legends game.
  /// 
  /// [gamePresenceCheckerInterval] defaults to 10 seconds.
  final Duration gamePresenceCheckerInterval;

  /// The interval used send an updated game summary via stream.
  /// 
  /// [gameSummaryInterval] defaults to 5 seconds.
  final Duration gameSummaryInterval;

  /// Wether to fetch the playerlist and put it into the summary.
  /// 
  /// If you set it to `false` the summaries playerList property will always be an empty list.
  /// 
  /// [fetchPlayerList] defaults to `true`.
  final bool fetchPlayerList;

  /// Wether to emit `null` on the game summary update stream when the game ended.
  /// 
  /// [emitNullForGameSummaryUpdateOnGameEnded] defaults to `true`.
  final bool emitNullForGameSummaryUpdateOnGameEnded;

  /// Wether to emit `0` on the game timer update stream when the game ended.
  /// 
  /// [emitResettedGameTimerOnGameEnded] defaults to `true`.
  final bool emitResettedGameTimerOnGameEnded;

  LCULiveGameWatcherConfig({
    this.disableLogging = false,
    this.gamePresenceCheckerInterval = const Duration(seconds: 10),
    this.gameSummaryInterval = const Duration(seconds: 5),
    this.fetchPlayerList = true,
    this.emitNullForGameSummaryUpdateOnGameEnded = true,
    this.emitResettedGameTimerOnGameEnded = true,
  });
}

class LCULiveGameWatcherSummary {
  dynamic gameStats;
  List<dynamic> eventData, playerList;

  LCULiveGameWatcherSummary({ required this.gameStats, required this.eventData, required this.playerList });

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
  
  static const _timeout = Duration(seconds: 3);

  final StreamController _gameFoundStreamController = StreamController.broadcast();
  final StreamController _gameEndedStreamController = StreamController.broadcast();
  final StreamController<int> _gameStartedStreamController = StreamController.broadcast();
  final StreamController<LCULiveGameWatcherSummary?> _gameSummaryUpdateStreamController = StreamController.broadcast();
  final StreamController<int> _gameTimerUpdateStreamController = StreamController.broadcast();

  /// [gameFound] emits one event when an active game was found.
  Stream get gameFound => _gameFoundStreamController.stream;

  /// [gameEnded] emits one event when an active game has ended.
  Stream get gameEnded => _gameEndedStreamController.stream;

  /// [gameStarted] emits one event when an active game has started and the summoners can interact with the game.
  Stream<int> get gameStarted => _gameStartedStreamController.stream;

  /// [gameSummaryUpdate] emits on the given interval of [LCULiveGameWatcherConfig] and emits a summary of the game data.
  Stream<LCULiveGameWatcherSummary?> get gameSummaryUpdate => _gameSummaryUpdateStreamController.stream;

  /// [gameTimerUpdate] emits an event every second after [gameStarted] emitted once.
  /// This can be used to show a timer in your app.
  /// Use the [formatSecondsToMMSS] method to format from seconds format to MM:SS format.
  Stream<int> get gameTimerUpdate => _gameTimerUpdateStreamController.stream;

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
  }

  void watch() {
    _checkForGamePresence();

    _gamePresenceWatcherTimer = Timer.periodic(_config.gamePresenceCheckerInterval, (timer) async {
      await _checkForGamePresence();
    });

    if (!_config.disableLogging) _logger.log('WATCHING');
  }

  void stop() {
    _gamePresenceWatcherTimer?.cancel();
    _gameWatcherTimer?.cancel();
    _gameTimerUpdateTimer?.cancel();
    gameInProgress = false;
    gameHasStarted = false;
    _internalGameTime = 0;

    if (!_config.disableLogging) _logger.log('STOPPED WATCHING');
  }

  Future _checkForGamePresence() async {
    try {
      await get(Uri.parse('${_storage.gameClientApi}gamestats')).timeout(_timeout);

      if (!gameInProgress) {
        gameInProgress = true;

        _startGameWatcherInterval();

        _gameFoundStreamController.add(null);

        if (!_config.disableLogging) _logger.log('GAME FOUND');
      }
    } catch (err) {
      if (gameInProgress) {
        gameInProgress = false;
        gameHasStarted = false;

        // GAME ENDED -> KILL GAME WATCHER
        _killGameWatcherInterval();
        _killGameTimerUpdateInterval();
        
        _gameEndedStreamController.add(null);

       if (!_config.disableLogging) _logger.log('GAME ENDED');
      }
    }
  }

  Future _startGameWatcherInterval() async {
    final summary = await getGameSummary();
    
    if (summary != null) {
      _gameSummaryUpdateStreamController.add(summary);

      print([!gameHasStarted, summary.eventData.firstWhereOrNull((e) => e['EventName'] == 'GameStart') != null]);
      
      if (!gameHasStarted && summary.eventData.firstWhereOrNull((e) => e['EventName'] == 'GameStart') != null) {
        gameHasStarted = true;

        double gt = summary.gameStats['gameTime'];
        int gameTime = gt < 1 ? gt.floor() : gt.ceil();
        
        _internalGameTime = gameTime;

        _gameStartedStreamController.add(gameTime);

        _startGameTimerUpdateInterval();

        if (!_config.disableLogging) _logger.log('GAME HAS STARTED');
      }
    }

    _gameWatcherTimer = Timer.periodic(_config.gameSummaryInterval, (_) async {
      final summary = await getGameSummary();

      if (summary != null) {
        _gameSummaryUpdateStreamController.add(summary);

        if (!gameHasStarted && summary.eventData.firstWhereOrNull((e) => e['EventName'] == 'GameStart') != null) {
          gameHasStarted = true;

          double gt = summary.gameStats['gameTime'];
          int gameTime = gt < 1 ? gt.floor() : gt.ceil();

          _internalGameTime = gameTime;

          _gameStartedStreamController.add(gameTime);

          _startGameTimerUpdateInterval();

          if (!_config.disableLogging) _logger.log('GAME HAS STARTED');
        }
      }
    });
  }

  void _killGameWatcherInterval() {
    if(_config.emitNullForGameSummaryUpdateOnGameEnded) _gameSummaryUpdateStreamController.add(null);

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

    final body = jsonDecode(utf8.decode(result.bodyBytes)) as Map;

    if (body.containsKey('Events')) {
      final eventData = body['Events'] as List;
      return eventData;
    }

    return [];
  }

  Future _requestPlayerList() async {
    Response result = await get(Uri.parse('${_storage.gameClientApi}playerlist')).timeout(_timeout);
    final playerList = jsonDecode(utf8.decode(result.bodyBytes));
    return playerList;
  }

  void _startGameTimerUpdateInterval() {
    _gameTimerUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _internalGameTime++;
      _gameTimerUpdateStreamController.add(_internalGameTime);  
    });
  }

  void _killGameTimerUpdateInterval() {
    _gameTimerUpdateTimer?.cancel();
    _internalGameTime = 0;
    
    if (_config.emitResettedGameTimerOnGameEnded) _gameTimerUpdateStreamController.add(_internalGameTime);
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

    _gameFoundStreamController.close();
    _gameEndedStreamController.close();
    _gameStartedStreamController.close();
    _gameSummaryUpdateStreamController.close();
    _gameTimerUpdateStreamController.close();
  }
}