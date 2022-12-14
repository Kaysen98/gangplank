import 'dart:async';
import 'dart:convert';

import 'package:gangplank/src/lcu_http_client_cache.dart';
import 'package:gangplank/src/wildcard.dart';
import 'package:http/http.dart' as http;

import 'package:gangplank/src/lcu_watcher.dart';
import 'package:gangplank/src/logging.dart';
import 'package:gangplank/src/storage.dart';

class LCUGetRouteToCache {
  /// The route that must be cached.
  ///
  /// Supports wildcards (e.g. `/lol-summoner/v1/summoners*` would match `/lol-summoner/v1/summoners?name=test`)
  final String route;

  /// The lifetime of this specific object in the cache.
  ///
  /// If not set, [cacheExpiration] defaults to the global duration.
  final Duration? cacheExpiration;

  LCUGetRouteToCache({
    required this.route,
    this.cacheExpiration,
  });

  Map<String, dynamic> toJson() => {
        'route': route,
        'cacheExpiration': cacheExpiration?.inSeconds,
      };

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

class LCUHttpClientConfig {
  /// Disables the logging for the [LCUHttpClient].
  ///
  /// [disableLogging] defaults to false.
  final bool disableLogging;

  /// The timeout used on HTTP requests.
  ///
  /// [requestTimeout] defaults to 8 seconds.
  final Duration requestTimeout;

  /// You can supply routes you want to cache.
  ///
  /// Usecase: Maybe you want to display the current lobby with it's members.
  /// On EVERY lobby update you get summoner data for all members.
  /// This builds up alot of requests to the summoner endpoint.
  /// Since the summoner data won't change frequently you can supply the endpoint route here to cache it.
  ///
  /// The application will then grab the data out of cache instead of requesting the data from LCU.
  ///
  /// You can use wildcards in the route parameter. E.g. `/lol-summoner/v1/summoners*` would also match `/lol-summoner/v1/summoners?name=test`.
  /// You can also use multiple wildcards like this: `/lol-summoner/*/summoners*`.
  /// If you want an equaliy check, don't use any wildcards.
  final List<LCUGetRouteToCache> getRoutesToCache;

  /// The lifetime of an object in the cache.
  ///
  /// [cacheExpiration] defaults to 30 minutes.
  final Duration cacheExpiration;

  LCUHttpClientConfig({
    this.disableLogging = false,
    this.requestTimeout = const Duration(seconds: 8),
    this.getRoutesToCache = const [],
    this.cacheExpiration = const Duration(minutes: 30),
  });
}

enum HttpMethod { get, post, delete, patch, put }

class LCUHttpClientException implements Exception {
  String message;
  int httpStatus;
  String? errorCode;

  LCUHttpClientException({required this.message, required this.httpStatus, this.errorCode});

  @override
  String toString() {
    return [httpStatus, errorCode, message].where((e) => e != null).join(' - ');
  }
}

class LCUHttpClient {
  late final GangplankLogger _logger;
  late final LCUStorage _storage;
  late final LCUWildcard _wildcard;
  late final LCUHttpClientCache _cache;

  // CONFIG

  late final LCUHttpClientConfig _config;

  LCUHttpClient({required LCUStorage storage, LCUHttpClientConfig? config}) {
    _storage = storage;
    _wildcard = LCUWildcard();

    _config = config ?? LCUHttpClientConfig();

    _logger = GangplankLogger(
      service: 'LCU-HTTP-CLIENT',
      storage: _storage,
    );

    _cache = LCUHttpClientCache();
  }

  /// Fires a GET request against the League client.
  ///
  /// Accepts [params].
  ///
  /// Throws [LCUHttpClientException] on error containing the message, http status and error code.
  /// You can call `toString()` on the exception to print the whole exception.
  ///
  /// Returns the requested resources payload either (from cache if route is supplied as an endpoint that should be cached).
  Future get(String endpoint, {Map<String, dynamic>? params}) async {
    final cachedResult = _cache.get(endpoint);

    if (cachedResult != null) {
      if (!_config.disableLogging) _logger.log('RETURNED FROM CACHE: $endpoint');

      return cachedResult;
    }

    final result = await _request(
      endpoint,
      HttpMethod.get,
      params: params,
    );

    LCUGetRouteToCache? foundEntry = _config.getRoutesToCache.firstWhereOrNull((e) => _wildcard.match(endpoint, e.route));

    if (foundEntry != null) {
      // ENTRY FOUND!
      // ROUTE SHOULD BE CACHED
      // IF CACHE EXPIRATION SET ON FOUND ENTRY USE IT, OTHERWISE GLOBAL CACHE EXPIRATION

      DateTime expiresIn = _cache.set(endpoint, result, foundEntry.cacheExpiration ?? _config.cacheExpiration);

      if (!_config.disableLogging) _logger.log('CACHED: $endpoint | EXPIRES: ${expiresIn.toIso8601String()}');
    }

    return result;
  }

  /// Fires a DELETE request against the League client.
  ///
  /// Accepts [params].
  ///
  /// You cannot perform HTTP requests before the LCUCredentials were set.
  /// That means you have to wait for the onClientStarted event from the LCUWatcher.
  /// Otherwise throws an assert error.
  ///
  /// Throws [LCUHttpClientException] on error containing the message, http status and error code.
  /// You can call `toString()` on the exception to print the whole exception.
  ///
  /// Returns the requested resources payload.
  Future delete(String endpoint, {Map<String, dynamic>? params}) async {
    return await _request(
      endpoint,
      HttpMethod.delete,
      params: params,
    );
  }

  /// Fires a POST request against the League client.
  ///
  /// Accepts a [body] and [params].
  ///
  /// You cannot perform HTTP requests before the LCUCredentials were set.
  /// That means you have to wait for the onClientStarted event from the LCUWatcher.
  /// Otherwise throws an assert error.
  ///
  /// Throws [LCUHttpClientException] on error containing the message, http status and error code.
  /// You can call `toString()` on the exception to print the whole exception.
  ///
  /// Returns the requested resources payload.
  Future post(String endpoint, {dynamic body, Map<String, dynamic>? params}) async {
    return await _request(
      endpoint,
      HttpMethod.post,
      body: body,
      params: params,
    );
  }

  /// Fires a PATCH request against the League client.
  ///
  /// Accepts a [body] and [params].
  ///
  /// You cannot perform HTTP requests before the LCUCredentials were set.
  /// That means you have to wait for the onClientStarted event from the LCUWatcher.
  /// Otherwise throws an assert error.
  ///
  /// Throws [LCUHttpClientException] on error containing the message, http status and error code.
  /// You can call `toString()` on the exception to print the whole exception.
  ///
  /// Returns the requested resources payload.
  Future patch(String endpoint, {dynamic body, Map<String, dynamic>? params}) async {
    return await _request(
      endpoint,
      HttpMethod.patch,
      body: body,
      params: params,
    );
  }

  /// Fires a PUT request against the League client.
  ///
  /// Accepts a [body] and [params].
  ///
  /// You cannot perform HTTP requests before the LCUCredentials were set.
  /// That means you have to wait for the onClientStarted event from the LCUWatcher.
  /// Otherwise throws an assert error.
  ///
  /// Throws [LCUHttpClientException] on error containing the message, http status and error code.
  /// You can call `toString()` on the exception to print the whole exception.
  ///
  /// Returns the requested resources payload.
  Future put(String endpoint, {dynamic body, Map<String, dynamic>? params}) async {
    return await _request(
      endpoint,
      HttpMethod.put,
      body: body,
      params: params,
    );
  }

  Future _request(String endpoint, HttpMethod method, {dynamic body, Map<String, dynamic>? params}) async {
    assert(_storage.credentials != null, 'LCU-CREDENTIALS NOT FOUND IN STORAGE. YOU MUST WAIT FOR THE LCU-WATCHER TO CONNECT BEFORE DOING HTTP REQUESTS.');

    String? url;

    try {
      LCUCredentials credentials = _storage.credentials!;

      url = 'https://${credentials.host}:${credentials.port}$endpoint';
      var bytes = utf8.encode('${credentials.username}:${credentials.password}');
      var base64Str = base64.encode(bytes);

      Map<String, String> headers = {'Accept': 'application/json', 'Authorization': 'Basic $base64Str', 'Content-Type': 'application/json'};

      if (params != null) {
        // ADD PARAMS TO URL

        url += '?${params.keys.map((e) => '$e=${params[e]}').join('&')}';
      }

      Uri uri = Uri.parse(url);

      http.Response? response;

      switch (method) {
        case HttpMethod.get:
          response = await http.get(uri, headers: headers).timeout(_config.requestTimeout);
          break;
        case HttpMethod.delete:
          response = await http.delete(uri, headers: headers).timeout(_config.requestTimeout);
          break;
        case HttpMethod.post:
          response = await http.post(uri, headers: headers, body: body != null ? jsonEncode(body) : null).timeout(_config.requestTimeout);
          break;
        case HttpMethod.patch:
          response = await http.patch(uri, headers: headers, body: body != null ? jsonEncode(body) : null).timeout(_config.requestTimeout);
          break;
        case HttpMethod.put:
          response = await http.put(uri, headers: headers, body: body != null ? jsonEncode(body) : null).timeout(_config.requestTimeout);
          break;
      }

      final responseBodyRaw = utf8.decode(response.bodyBytes);
      final responseBody = jsonDecode(responseBodyRaw.isEmpty ? '{}' : responseBodyRaw);

      if (responseBody is Map && (responseBody['errorCode'] != null || responseBody['httpStatus'] != null || responseBody['message'] != null)) {
        throw LCUHttpClientException(
          message: responseBody['message'],
          httpStatus: responseBody['httpStatus'],
          errorCode: responseBody['errorCode'],
        );
      }

      if (!_config.disableLogging) _logger.log('SUCCESSFULLY RECEIVED RESPONSE FROM $url');

      return responseBody;
    } catch (err) {
      if (!_config.disableLogging) _logger.err('ERROR OCCURED REQUESTING $url', err);

      if (err is TimeoutException) {
        throw LCUHttpClientException(
          httpStatus: 408,
          message: 'The request timed out after ${_config.requestTimeout.inSeconds} seconds',
        );
      }

      if (err is LCUHttpClientException) rethrow;

      throw LCUHttpClientException(
        message: err.toString(),
        httpStatus: 400,
      );
    }
  }

  void removeKeyFromCache(String url) {
    _cache.remove(url);
  }

  void clearCache() {
    _cache.clear();
  }
}

extension IterableExtension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
