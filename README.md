<!-- 
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/guides/libraries/writing-package-pages). 

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-library-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/developing-packages). 
-->

<p><img src="https://github.com/Kaysen98/gangplank/raw/main/assets/barrel.webp" width="100"/></p>

# Gangplank

Gangplank is a package designed to ease the use of the LCU (League client update) API. 
It provides multiple functionalities that are described below.
This package ONLY supports windows and macOS at the moment.

## Example app using Gangplank

<img src="https://github.com/Kaysen98/gangplank/raw/main/assets/1.jpg">
<img src="https://github.com/Kaysen98/gangplank/raw/main/assets/2.jpg">

# Features

1. LCUWatcher watches your League client and will notify you when the client is started and/or closed.
2. LCUSocket is responsible for the websocket connection. It connects to the League client. You can subscribe to events you want to listen to.
3. LCUHttpClient provides the most common HTTP methods to send HTTP requests to the League client (e.g. create a lobby, start matchmaking etc.).
4. LCULiveGameWatcher watches your League gameclient and will notify in several ways (more below).

# Usage
## Beforehand
The LCUWatcher, LCUSocket, LCUHttpClient and LCULiveGameWatcher shall be solely instantiated by using the Gangplank class. That ensures everything is working as expected. If you try to create an instance of one service multiple times using the same Gangplank instance it will throw an assert error.

```dart
final gp = Gangplank(
    // DISABLE LOGGING FOR WHOLE PACKAGE
    
    disableLogging: true,
);

final watcher = gp.createLCUWatcher(
    config: LCUWatcherConfig(
        // DISABLE LOGGING ONLY FOR LCUWATCHER
        disableLogging: true,

        // THE INTERVAL USED TO CHECK WHETHER THE LEAGUE OF LEGENDS PROCESS EXISTS OR NOT
        processCheckerInterval: const Duration(seconds: 2),
    )
);
final socket = gp.createLCUSocket();
final httpClient = gp.createLCUHttpClient();
final liveGameWatcher = gp.createLCULiveGameWatcher();
```

Every service listed can take a config object allowing you to change the behaviour.

## HttpOverrides

Before you start using this package, make sure you override HTTP globally to prevent handshake exceptions when connecting to the LCU.

```dart
void main() {
  HttpOverrides.global = GangplankHttpOverrides();

  runApp(const GangplankExampleApp());
}
```

## LCUWatcher and LCUSocket

The LCUWatcher is the first instance you need to use for the other services to work correctly. It watches your League client and extracts the needed credentials to connect to the League client. You CANNOT use the LCUSocket or LCUHttpClient before the onClientStarted event fired. After the LCUWatcher fired the onClientStarted event you can connect to the socket. When the socket is successfully connected the onConnect event will be fired. If the League client is closed and opened again all services will work again naturally, no need to handle anything yourself :)

```dart
final gp = Gangplank();
final watcher = gp.createLCUWatcher();
final socket = gp.createLCUSocket();

watcher.onClientStarted.listen((credentials) {
    // IS CALLED WHEN THE LCUWATCHER FOUND A RUNNING LEAGUE CLIENT INSTANCE
    // NOW YOU CAN SAFELY USE THE LCUHTTPCLIENT

    /* THE CLIENT IS STARTED, YOU CAN NOW START CONNECTING TO THE WEBSOCKET THAT THE LEAGUE CLIENT EXPOSES*/
    // WHEN THE SOCKET SUCCESSFULLY CONNECTED IT WILL FIRE THE onConnect event

    socket.connect();
});

watcher.onClientClosed.listen((_) {
    // THE LEAGUE CLIENT IS CLOSED
});

socket.onConnect.listen((_) {
    // THE SOCKET IS NOW CONNECTED
});

socket.onDisconnect.listen((_) {
    // THE SOCKET IS NOW DISCONNECTED
});

// START WATCHING

watcher.watch();
```

If you want to you can also manually make the LCUWatcher stop watching or disconnect the LCUSocket.

```dart
watcher.stopWatching();
socket.disconnect();
```

## Subscribe to socket events
You can subscribe to the same events multiple times in your application if you need it in different widgets/components/services. If the LCUSocket disconnects and reconnects the subscriptions will stay and will not be disposed. That means subscribing once is enough.

```dart
socket.subscribe('*', (event) {
    // HERE YOU RECEIVE ALL EVENTS THE LEAGUE CLIENT FIRES
});

socket.subscribe('/lol-lobby/v2/*', (event) {
    // YOU CAN USE WILDCARDS AT THE END OF THE GIVEN PATH
    // USING WILDCARDS WILL MATCH ALL EVENTS THAT START WITH GIVEN PATH BEFORE THE WILDCARD OPERATOR
});

socket.subscribe('*/v2/lobby', (event) {
    // YOU CAN USE WILDCARDS AT THE START OF THE GIVEN PATH
    // USING WILDCARDS WILL MATCH ALL EVENTS THAT END WITH GIVEN PATH BEFORE THE WILDCARD OPERATOR
});

socket.subscribe('/lol-chat/v1/conversations/*/messages', (event) {
    // YOU CAN USE WILDCARDS IN-BETWEEN THE GIVEN PATH
    // USING WILDCARDS WILL MATCH ALL EVENTS THAT START AND END WITH GIVEN PATH BETWEEN THE WILDCARD OPERATOR
});

socket.subscribe('/lol-lobby/v2/lobby', (event) {
    // YOU CAN ALSO JUST MATCH THE PATH COMPLETELY
});

// UNSUBSCRIBE FROM EVENT
socket.unsubscribe('/lol-lobby/v2/lobby');

// SUBSCRIBE AND UNSUBSCRIBE FROM A SPECIFIC EVENT LISTENER BY FUNCTION (NO ANONYMOUS FUNCTION)

socket.subscribe('/lol-lobby/v2/lobby', onLobbyEvent);

socket.unsubscribeSpecific(onLobbyEvent);

void onLobbyEvent(EventResponse data) => print(data);

// FIRE AN EVENT MANUALLY TO TEST AND MOCK EVENT LISTENERS

socket.fireEvent(
    '/lol-lobby/v2/lobby', 
    ManualEventResponse(
        uri: '/lol-lobby/v2/lobby', 
        data: { 'mockedData': true }
    ),
);

// UPPER WILL RESULT THIS EVENT LISTENER TO FIRE AND EMIT THE DATA GIVEN ABOVE

socket.subscribe('/lol-lobby/v2/lobby', (event) {
    // EVENT.uri = '/lol-lobby/v2/lobby';
    // EVENT.data = {'mockedData': true };
});
```

## LUCHttpClient (perform HTTP requests)
As mentioned above, HTTP requests are only safe to perform when the onClientStarted event was fired. Otherwise an assert error will be thrown. The LCUHttpClient uses it's own exception class. This exception class called LCUHttpClientException includes the error message, the http status and error code provided by the League client when an error occurs.

### Create a lobby or leave it
```dart
final gp = Gangplank();

// OF COURSE ONLY USABLE AFTER THE WATCHER FIRED THE ONCLIENTSTARTED EVENT

// YOU CAN PASS ENDPOINT ROUTES THAT SHALL BE CACHED BASED ON WHICH MATCH TYPE AND FOR HOW LONG
// THE CACHE EXPIRATION IS OPTIONAL, IT WILL DEFAULT TO THE GLOBAL CACHE EXPIRATION THEN

final httpClient = gp.createLCUHttpClient(
    config: LCUHttpClientConfig(
        getRoutesToCache: [
          LCUGetRouteToCache(
            route: '/lol-summoner/v1/current',
            cacheExpiration: const Duration(minutes: 60),
            matchType: LCUGetRouteToCacheMatchType.contains
          ),
          LCUGetRouteToCache(
            route: '/lol-summoner/v1/summoners',
            cacheExpiration: const Duration(minutes: 120),
            matchType: LCUGetRouteToCacheMatchType.startsWith
          )
        ],
        cacheExpiration: const Duration(minutes: 20),
    ),
);

try {
    // QUEUEID 440 WILL RESULT IN A FLEX RANKED LOBBY

    await httpClient.post('/lol-lobby/v2/lobby', body: { 'queueId': 440 });
} catch (err) {
    // USING TOSTRING() WILL PRINT ALL PROPERTIES OF THE EXCEPTION

    print(err.toString());
}

try {
    // LEAVE THE CURRENT LOBBY

    await httpClient.delete('/lol-lobby/v2/lobby');
} catch (err) {
    // USING TOSTRING() WILL PRINT ALL PROPERTIES OF THE EXCEPTION

    print(err.toString());
}
```

## LCULiveGameWatcher
The LCULiveGameWatcher communicates with the game client api. The game client is the actual application that is launched after champselect in which you actively play the game. The LCULiveGameWatcher works independently from the other services and can be used without dependencies unlike the LCUSocket and LCUHttpClient which rely on the League client to be running first. This service will expose the following API.

Subscribe to a stream which emits ..
* When an ongoing game is found or terminated
* When an ongoing game is fully loaded and started (the player can interact ingame)
* When you receive an update on data exposed by the gameclient (gameSummaryUpdate)
* When the ingame timer changes

Following data is requested on gameSummaryUpdate:
* The gamestats (endpoint: gamestats)
* The eventdata (endpoint: eventdata)
* The whole playerlist (endpoint: playerlist) <-- Can be disabled
```dart
final gp = Gangplank();

final liveGameWatcher = gp.createLCULiveGameWatcher();

liveGameWatcher.onGameFound.listen((_) {
    // EMITS WHEN AN ONGOING GAME IS FOUND
});

liveGameWatcher.onGameEnded.listen((_) {
    // EMITS WHEN THE ONGOING GAME ENDS OR IS TERMINATED
});

liveGameWatcher.onGameStarted.listen((gameTime) {
    // EMITS WHEN THE ONGOING GAME ACTUALLY STARTED WITH THE CURRENT GAMETIME
});

liveGameWatcher.onGameSummaryUpdate.listen((summary) {
    /* EMITS A GAMESUMMARY OF DATA EXPOSED BY THE GAMECLIENT
    EMITS IN AN INTERVAL YOU CAN CONFIGURE YOURSELF */
});

liveGameWatcher.onGameTimerUpdate.listen((time) {
    // EMITS WHEN THE GAME TIMER IS UPDATED -> EVERY SECOND ONCE

    /* THIS FUNCTION WILL CONVERT SECONDS INTO THE MM:SS FORMAT
    WHICH CAN BE USED TO DISPLAY THE CURRENT INGAME TIMER*/

    print(liveGameWatcher.formatSecondsToMMSS(time));
});

// START WATCHING FOR THE GAMECLIENT

liveGameWatcher.watch();
```
You can also pass in a config object to the createLCULiveGameWatcher function.
```dart
final liveGameWatcher = gp.createLCULiveGameWatcher(
    config: LCULiveGameWatcherConfig(
        disableLogging: true,
        fetchPlayerList: false,
        gamePresenceCheckerInterval: const Duration(seconds: 5),
        gameSummaryInterval: const Duration(seconds: 2),
        emitNullForGameSummaryUpdateOnGameEnded: false,
        emitResettedGameTimerOnGameEnded: false,
    ),
);
```

If you want to you can also manually make the LCULiveGameWatcher stop watching.

```dart
liveGameWatcher.stopWatching();
```

## Dispose resources
Most likely the Gangplank instance will be used the whole lifetime of your application in most cases, but if you decide to only use it as a part of your application be sure to call the dispose function on the Gangplank instance.

```dart
gp.dispose();
```
