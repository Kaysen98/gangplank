import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gangplank/src/lcu_watcher.dart';
import 'package:gangplank/src/logging.dart';
import 'package:gangplank/src/storage.dart';

class EventResponse {
  final String uri;
  final dynamic data;

  EventResponse({
    required this.uri,
    this.data,
  });

  Map<String, dynamic> toJson() => {
        'uri': uri,
        'data': data,
      };

  Map<String, dynamic> toJsonWithoutData() => {
        'uri': uri,
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

  final StreamController _onConnectStreamController =
      StreamController.broadcast();
  final StreamController _onDisconnectStreamController =
      StreamController.broadcast();

  Stream get onConnect => _onConnectStreamController.stream;
  Stream get onDisconnect => _onDisconnectStreamController.stream;
  bool get isConnected => _connected;

  bool _connected = false;
  Timer? _tryConnectInterval;

  final Map<String, List<Function>> _subscriptions = {};
  WebSocket? _socket;

  LCUSocket({required LCUStorage storage}) {
    _storage = storage;

    _logger = GangplankLogger(
      service: 'LCUSocket',
      storage: _storage,
    );
  }

  /// Tries to connect to the LCUSocket. On success triggers the [onConnect] event.
  ///
  /// You cannot connect to the LCUSocket before the LCUCredentials were set.
  ///
  /// That means you need to call this function in the onClientStarted event from the LCUWatcher.
  Future<void> connect() async {
    assert(_storage.credentials != null,
        'LCU-CREDENTIALS NOT FOUND IN STORAGE. YOU MUST WAIT FOR THE LCU-WATCHER TO CONNECT BEFORE YOU TRY TO CONNECT TO THE LCUSocket.');

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
      _tryConnectInterval =
          Timer.periodic(const Duration(seconds: 5), (_) async {
        await _connect();

        if (isConnected) _tryConnectInterval!.cancel();
      });
    }
  }

  Future _connect() async {
    try {
      LCUCredentials? credentials = _storage.credentials;

      if (credentials == null) {
        throw Exception(
            'LCU-CREDENTIALS NOT PROVIDED. YOU MUST WAIT FOR THE LCU-WATCHER TO CONNECT BEFORE YOU TRY TO CONNECT TO THE LCUSocket.');
      }

      _logger.log('TRYING TO CONNECT');

      String url =
          'wss://${credentials.username}:${credentials.password}@${credentials.host}:${credentials.port}/';
      var bytes =
          utf8.encode('${credentials.username}:${credentials.password}');
      var base64Str = base64.encode(bytes);

      Map<String, dynamic> headers = {'Authorization': 'Basic $base64Str'};

      _socket = await WebSocket.connect(url,
          headers: headers,
          customClient: HttpClient(
            context: _storage.securityContext,
          ));

      _connected = true;
      _onConnectStreamController.add(null);

      _logger.log('CONNECTED!');

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

        EventResponse? response = EventResponse(
          uri: parsedPayload['uri'],
          data: parsedPayload['data'],
        );

        for (String key in _subscriptions.keys) {
          if (key == '*') {
            // KEY IS ALL -> PIPE ALL EVENTS

            for (Function callback in _subscriptions[key]!) {
              callback(response);
            }
          } else if (key.startsWith('*')) {
            // KEY IS A WILDCARD -> PROCEED IF IT STARTS WITH KEY

            if (response.uri.endsWith(key.replaceAll('*', ''))) {
              // FOUND KEY WITH WILDCARD

              for (Function callback in _subscriptions[key]!) {
                callback(response);
              }
            }
          } else if (key.endsWith('*')) {
            // KEY IS A WILDCARD -> PROCEED IF IT STARTS WITH KEY

            if (response.uri.startsWith(key.replaceAll('*', ''))) {
              // FOUND KEY WITH WILDCARD

              for (Function callback in _subscriptions[key]!) {
                callback(response);
              }
            }
          } else {
            // IS NO WILDCARD -> PROCEED NORMALLY

            if (key == response.uri) {
              // FOUND REGISTERED LISTENER IN SUBSCRIPTIONS

              for (Function callback in _subscriptions[key]!) {
                callback(response);
              }
            }
          }
        }
      }, onDone: () async {
        if (_connected) {
          _logger.log('DISCONNECTED!');
          _connected = false;
          _onDisconnectStreamController.add(null);
        }
      });

      _socket!.add(jsonEncode([5, 'OnJsonApiEvent']));
    } catch (err) {
      if (_connected) {
        _logger.log('DISCONNECTED!');
        _connected = false;
        _onDisconnectStreamController.add(null);
      } else {
        _logger.log(err.toString());
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
  /// You can also provide a wildcard (e.g. `*/current-summoner` or `/lol-summoner/*`).
  /// By providing a wildcard every route you subscribed to will be called.
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

  /// Unsubscribes an eventlistener by path.
  void unsubscribe(String path) {
    // REMOVE FROM SUBSCRIPTION MAP

    _subscriptions.remove(path);
  }

  /// Call dispose to clean all subscriptions when you are finished using the LCUSocket.
  void dispose() {
    disconnect();
    _onConnectStreamController.close();
    _onDisconnectStreamController.close();
    _socket?.close();
  }
}
