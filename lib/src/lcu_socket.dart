import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gangplank/src/lcu_socket_debouncer.dart';
import 'package:gangplank/src/lcu_watcher.dart';
import 'package:gangplank/src/logging.dart';
import 'package:gangplank/src/storage.dart';
import 'package:gangplank/src/wildcard.dart';

enum EventResponseType {
  create,
  update,
  delete,
}

extension EventResponseTypeParser on String {
  EventResponseType toEventResponseType() {
    switch (toLowerCase()) {
      case 'create':
        return EventResponseType.create;
      case 'update':
        return EventResponseType.update;
      case 'delete':
        return EventResponseType.delete;
      default:
        return EventResponseType.update;
    }
  }
}

extension EventResponseTypeExtension on EventResponseType {
  String get asString {
    switch (this) {
      case EventResponseType.create:
        return 'create';
      case EventResponseType.update:
        return 'update';
      case EventResponseType.delete:
        return 'delete';
      default:
        return 'update';
    }
  }
}

class LCUSocketConfig {
  /// Disables the logging for the [LCUSocket].
  ///
  /// [disableLogging] defaults to `false`.
  final bool disableLogging;

  /// Disables the logging for the [LCUSocket] debouncer.
  ///
  /// [disableLoggingDebouncer] defaults to `false`.
  final bool disableLoggingDebouncer;

  /// The interval used to try to connect the LCUSocket on failure.
  ///
  /// [tryConnectInterval] defaults to 5 seconds.
  final Duration tryConnectInterval;

  /// The duration used to debounce events identified by uri/endpoint.
  ///
  /// The LCU tends to send events multiple times in a very fast manner. The debouncer "waits" for the given duration and only emits the last event.
  /// If you receive an event for the endpoint `/lol-lobby/v2/lobby` e.g. the LCU will most probably send 1-4 events and the debouncer will sort out all events but the last one.
  /// You will receive the newest event then.
  ///
  /// A time span of 500 milliseconds is most balanced and will filter out duplicate events just fine.
  ///
  /// NOTE: By debouncing events you cannot trust the [EventResponseType] of emitted events, since only the newest event is going to be emitted.
  /// Which means if you delete a lobby and create it again in the same time period as [debounceDuration], the delete event will be skipped.
  ///
  /// [debounceDuration] defaults to null, which means no debouncer is used.
  final Duration? debounceDuration;

  LCUSocketConfig({this.disableLogging = false, this.disableLoggingDebouncer = false, this.tryConnectInterval = const Duration(seconds: 5), this.debounceDuration});
}

class EventResponse {
  final String uri;
  final EventResponseType eventType;
  final dynamic data;

  EventResponse({
    required this.uri,
    this.eventType = EventResponseType.update,
    this.data,
  });

  Map<String, dynamic> toJson() => {
        'uri': uri,
        'eventType': eventType.asString,
        'data': data,
      };

  Map<String, dynamic> toJsonWithoutData() => {
        'uri': uri,
        'eventType': eventType.asString,
      };

  Map<String, dynamic> toJsonOnlyData() => {
        'data': data,
      };

  @override
  String toString() {
    return jsonEncode(toJson());
  }

  String toStringOnlyData() {
    return jsonEncode(toJsonOnlyData());
  }
}

class ManualEventResponse extends EventResponse {
  ManualEventResponse({
    required super.uri,
    super.eventType,
    super.data,
  });
}

class LcuMessageType {
  static const int welcome = 0;
  static const int prefix = 1;
  static const int call = 2;
  static const int callResult = 3;
  static const int callError = 4;
  static const int subscribe = 5;
  static const int unsubscribe = 6;
  static const int publish = 7;
  static const int event = 8;
}

class LCUSocket {
  late final GangplankLogger _logger;
  late final LCUStorage _storage;
  late final LCUWildcard _wildcard;
  late final LCUSocketDebouncer _debouncer;

  // CONFIG

  late final LCUSocketConfig _config;

  final StreamController _onConnectStreamController = StreamController.broadcast();
  final StreamController _onDisconnectStreamController = StreamController.broadcast();

  Stream get onConnect => _onConnectStreamController.stream;
  Stream get onDisconnect => _onDisconnectStreamController.stream;
  bool get isConnected => _connected;
  WebSocket? get nativeSocket => _socket;
  Map<String, List<Function(EventResponse)>> get subscriptions => _subscriptions;

  bool _connected = false;
  Timer? _tryConnectInterval;

  final Map<String, List<Function(EventResponse)>> _subscriptions = {};
  WebSocket? _socket;

  LCUSocket({required LCUStorage storage, LCUSocketConfig? config}) {
    _storage = storage;
    _wildcard = LCUWildcard();

    _config = config ?? LCUSocketConfig();

    _logger = GangplankLogger(
      service: 'LCUSocket',
      storage: _storage,
    );

    _debouncer = LCUSocketDebouncer(
      debounceDuration: _config.debounceDuration,
    );

    _debouncer.onDebounce.listen((debounceResponse) {
      for (String key in _subscriptions.keys) {
        if (key == '*') {
          // KEY IS ALL -> PIPE ALL EVENTS

          for (Function callback in _subscriptions[key]!) {
            callback(debounceResponse.event);
          }
        } else if (_wildcard.match(debounceResponse.event.uri, key)) {
          // PATTERN MATCHED

          for (Function callback in _subscriptions[key]!) {
            callback(debounceResponse.event);
          }
        }
      }

      if (!_config.disableLogging && !_config.disableLoggingDebouncer && _config.debounceDuration != null) {
        _logger.log('${debounceResponse.event.uri} DEBOUNCED - EMITTED NEWEST EVENT FROM ${debounceResponse.eventsAccumulated} EVENT(S)');
      }
    });
  }

  /// Tries to connect to the LCUSocket. On success triggers the [onConnect] event.
  ///
  /// You cannot connect to the LCUSocket before the LCUCredentials were set.
  ///
  /// That means you need to call this function in the onClientStarted event from the LCUWatcher.
  Future<void> connect() async {
    assert(_storage.credentials != null, 'LCU-CREDENTIALS NOT FOUND IN STORAGE. YOU MUST WAIT FOR THE LCU-WATCHER TO CONNECT BEFORE YOU TRY TO CONNECT TO THE LCUSocket.');

    // WAIT ONE SECOND TO WAIT FOR THE CLIENT WHEN IT JUST STARTED

    await Future.delayed(const Duration(seconds: 1));

    _startConnecting();
  }

  /// Disconnects the current LCUSocket connection and triggers the [onDisconnect] event.
  Future<void> disconnect() async {
    await _socket?.close();
    _tryConnectInterval?.cancel();
    _connected = false;
    _onDisconnectStreamController.add(null);
  }

  Future _startConnecting() async {
    await _connect();

    if (!isConnected) {
      _tryConnectInterval = Timer.periodic(_config.tryConnectInterval, (_) async {
        await _connect();

        if (isConnected) _tryConnectInterval!.cancel();
      });
    }
  }

  Future _connect() async {
    try {
      LCUCredentials? credentials = _storage.credentials;

      if (credentials == null) {
        throw Exception('LCU-CREDENTIALS NOT PROVIDED. YOU MUST WAIT FOR THE LCU-WATCHER TO CONNECT BEFORE YOU TRY TO CONNECT TO THE LCUSocket.');
      }

      if (!_config.disableLogging) _logger.log('TRYING TO CONNECT');

      String url = 'wss://${credentials.username}:${credentials.password}@${credentials.host}:${credentials.port}/';
      var bytes = utf8.encode('${credentials.username}:${credentials.password}');
      var base64Str = base64.encode(bytes);

      Map<String, dynamic> headers = {'Authorization': 'Basic $base64Str'};

      _socket = await WebSocket.connect(url,
          headers: headers,
          customClient: HttpClient(
            context: _storage.securityContext,
          ));

      _connected = true;
      _onConnectStreamController.add(null);

      if (!_config.disableLogging) _logger.log('CONNECTED!');

      _socket!.listen((content) {
        if (content is String && content.isEmpty) {
          // ONLY HANDLE EVENT UPDATES -> NO CALL ERRORS OR ANYTHING OTHER

          return;
        }

        List<dynamic> parsedContent = jsonDecode(content);

        if (parsedContent[0] != LcuMessageType.event) {
          // WE ONLY WANT EVENTS

          return;
        }

        Map parsedPayload = parsedContent[2];
        String uri = parsedPayload['uri'];

        for (String key in _subscriptions.keys) {
          if (key == '*' || _wildcard.match(uri, key)) {
            // KEY IS ALL -> PIPE ALL EVENTS

            EventResponse response = EventResponse(
              uri: uri,
              eventType: parsedPayload['eventType'].toString().toEventResponseType(),
              data: parsedPayload['data'],
            );

            _debouncer.add(response);
          }
        }
      }, onDone: () async {
        if (_connected) {
          if (!_config.disableLogging) _logger.log('DISCONNECTED!');
          _connected = false;
          _onDisconnectStreamController.add(null);
        }
      });

      _socket!.add(jsonEncode([5, 'OnJsonApiEvent']));
    } catch (err) {
      if (_connected) {
        if (!_config.disableLogging) _logger.log('DISCONNECTED!');
        _connected = false;
        _onDisconnectStreamController.add(null);
      } else {
        if (!_config.disableLogging) _logger.log(err.toString());
      }
    }
  }

  /// Prints all currently active subscriptions to the console. Only works if you haven't disabled logging prior.
  printSubscriptions() {
    assert(!_storage.disableLogging, 'YOU DISABLED LOGGING.');

    if (_subscriptions.isEmpty) {
      _logger.log('NO ACTIVE SUBSCRIPTIONS.');
      return;
    }

    _logger.log('-------------------------------------------------');
    _logger.log('CURRENT SUBSCRIBED ROUTES');

    for (String key in _subscriptions.keys) {
      _logger.log('URI: $key - SUBSCRIPTIONS: ${_subscriptions[key]!.length}');
    }

    _logger.log('-------------------------------------------------');
  }

  /// Subscribe to a League client route.
  ///
  ///
  /// You can provide a path that matches 100% (e.g. `/lol-summoner/v1/current-summoner`).
  ///
  ///
  /// You can provide wildcards. E.g. `*/current-summoner` and `/lol-summoner/v1/*` would also match `/lol-summoner/v1/current-summoner`.
  /// You can also use multiple wildcards like this: `/lol-summoner/*/current*`.
  /// If you want an equaliy check, don't use any wildcards.
  ///
  ///
  /// This is mostly helpful when you need to listen to any change of any friend in your friendslist (e.g `/lol-game-client-chat/v1/buddies/insert-buddy-name-here`).
  /// Since you dont want to subscribe to each buddy in your friends list, using the route with wildcard makes it very easy (e.g `/lol-game-client-chat/v1/buddies/*`).
  ///
  /// You can also provide only *. That way you will receive every event the socket fires. Caution, these should only be used for debugging, since there are many
  /// events fired.
  ///
  /// Only subscribe once since the subscriptions stay even when the client closes and the socket is closed and/or reconnects!
  void subscribe(String path, Function(EventResponse) callback) {
    if (!_subscriptions.containsKey(path)) {
      // ADD THE PATH TO THE SUBSCRIPTION MAP

      _subscriptions[path] = [callback];
    } else {
      // SUBSCRIPTION MAP ALREADY HAS THIS PATH - PUSH CALLBACK TO EVENTCALLBACK ARRAY

      _subscriptions[path]?.add(callback);
    }
  }

  /// Unsubscribes all eventlisteners by path.
  void unsubscribe(String path) {
    // REMOVE FROM SUBSCRIPTION MAP

    _subscriptions.remove(path);
  }

  /// Unsubscribes specific eventlistener by function.
  ///
  /// To make this work you need to have a named function in the subscribe call instead of an anonymous function.
  void unsubscribeSpecific(Function(EventResponse) function) {
    // REMOVE FROM SUBSCRIPTION MAP

    for (String key in _subscriptions.keys) {
      if (_subscriptions[key]!.contains(function)) {
        _subscriptions[key]!.removeWhere((e) => e == function);
      }
    }
  }

  /// Unsubscribes all subscriptions
  void clearSubscriptions() {
    _subscriptions.clear();
  }

  /// Fire an event manually providing [path] and [manualEventResponse].
  ///
  /// [ManualEventResponse] has the same implementation as [EventResponse] but you can differentiate a normal from a manual/test event if you check the type.
  ///
  /// If you subscribed to `/test` e.g. and you call [fireEvent] with the path `/test` it will raise an event in your subscription handler.
  void fireEvent(String path, ManualEventResponse manualEventResponse) {
    if (_subscriptions.containsKey(path)) {
      _subscriptions[path]!.forEach((callback) => callback(manualEventResponse));
    }
  }

  /// Call dispose to clean all subscriptions when you are finished using the LCUSocket.
  void dispose() {
    disconnect();
    _onConnectStreamController.close();
    _onDisconnectStreamController.close();
    _socket?.close();
    _debouncer.dispose();
  }
}
