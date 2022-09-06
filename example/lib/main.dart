import 'dart:io';

import 'package:gangplank/gangplank.dart';
import 'package:flutter/material.dart';

void main() {
  HttpOverrides.global = GangplankHttpOverrides();

  runApp(const GangplankExampleApp());
}

class GangplankExampleApp extends StatelessWidget {
  const GangplankExampleApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gangplank',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
      ),
      home: const GangplankExamplePage(),
    );
  }
}

class GangplankExamplePage extends StatefulWidget {
  const GangplankExamplePage({Key? key}) : super(key: key);

  @override
  State<GangplankExamplePage> createState() => _GangplankExamplePageState();
}

class _GangplankExamplePageState extends State<GangplankExamplePage> {
  late Gangplank gp;
  late LCUWatcher watcher;
  late LCUSocket socket;
  late LCUHttpClient httpClient;
  late LCULiveGameWatcher liveGameWatcher;

  LCUCredentials? _credentials;
  List<EventResponse> events = [];
  String? currentGameflowPhase;
  int currentLiveGameTime = 0;

  @override
  void initState() {
    super.initState();

    gp = Gangplank();

    watcher = gp.createLCUWatcher();
    socket = gp.createLCUSocket();
    httpClient = gp.createLCUHttpClient();
    liveGameWatcher = gp.createLCULiveGameWatcher(
      config: LCULiveGameWatcherConfig(
        disableLogging: false,
      ),
    );

    watcher.onClientStarted.listen((credentials) async {
      // CLIENT HAS STARTED
      // NOW WE CAN CONNECT TO THE SOCKET
      // IF YOU TRY TO CONNECT TO SOCKET BEFORE THIS EVENT YOU WILL RAISE AN EXCEPTION (CREDENTIALS NOT PROVIDED)

      _credentials = credentials;

      socket.connect();

      setState(() {});
    });

    watcher.onClientClosed.listen((_) {
      // CLIENT WAS CLOSED
      /* IF THE LCU-SOCKET CONNECTED IT WILL DISCONNECT AUTOMATICALLY
      SINCE THE LEAGUE CLIENT WAS CLOSED*/

      setState(() {});
    });

    socket.onConnect.listen((_) {
      // SOCKET CONNECTED

      setState(() {});
    });

    socket.onDisconnect.listen((_) {
      // SOCKET DISCONNECTED

      events.clear();
      setState(() {});
    });

    // START WATCHING THE LCU

    watcher.watch();

    /* SUBSCRIBE TO EVENTS -> REMEMBER! ONLY SUBSCRIBE ONCE EVEN WHEN THE SOCKET CLOSES/RECONNECTS
    THE SUBSCRIPTIONS ALWAYS STAY!*/

    socket.subscribe('/lol-lobby/v2/lobby', (event) {
      events.add(event);
      setState(() {});
    });

    socket.subscribe('/lol-gameflow/v1/gameflow-phase', (event) {
      currentGameflowPhase = event.data;
      events.add(event);
      setState(() {});
    });

    socket.subscribe('/lol-game-client-chat/v1/buddies/*', (event) {
      events.add(event);
      setState(() {});
    });
  
    liveGameWatcher.gameFound.listen((_) {
      print('GAME HAS BEEN FOUND');
      setState(() {});
    });

    liveGameWatcher.gameEnded.listen((_) {
      print('GAME HAS ENDED');
      setState(() {});
    });

    liveGameWatcher.gameStarted.listen((gameTime) {
      print('GAME HAS STARTED $gameTime');
      setState(() {});
    });

    liveGameWatcher.gameSummaryUpdate.listen((summary) {
      //print(summary?.toJson());
      setState(() {});
    });
    
    liveGameWatcher.gameTimerUpdate.listen((time) {
      currentLiveGameTime = time;
      print(currentLiveGameTime);
      setState(() {});
    });

    liveGameWatcher.watch();
  }

  @override
  void dispose() {
    gp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Gangplank',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Card(
                margin: EdgeInsets.zero,
                child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('LCU-CREDENTIALS'),
                        const SizedBox(
                          height: 10,
                        ),
                        Text(
                          _credentials == null ? 'Not found yet.' : _credentials.toString(),
                        ),
                      ],
                    ))),
            const SizedBox(
              height: 10,
            ),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('LCU-STATUSES'),
                      const SizedBox(
                        height: 10,
                      ),
                      ListTile(
                        leading: _buildStatusDot(true),
                        title: Text(currentGameflowPhase != null ? 'Gameflowphase: $currentGameflowPhase' : 'Gameflowphase: No gameflow found yet.'),
                        dense: true,
                      ),
                      ListTile(
                        leading: _buildStatusDot(watcher.clientIsRunning),
                        title: Text(watcher.clientIsRunning
                            ? 'LCU is running'
                            : 'LCU is not running'),
                        dense: true,
                      ),
                      ListTile(
                        leading: _buildStatusDot(socket.isConnected),
                        title: Text(socket.isConnected
                            ? 'LCU-Socket is connected'
                            : 'LCU-Socket is not connected'),
                        dense: true,
                      ),
                      ListTile(
                        leading: _buildStatusDot(liveGameWatcher.gameInProgress),
                        title: Text(liveGameWatcher.gameInProgress
                            ? 'Player is currently ingame'
                            : 'Player is currently not ingame'),
                        dense: true,
                      ),
                      ListTile(
                        leading: _buildStatusDot(liveGameWatcher.gameHasStarted),
                        title: Text(liveGameWatcher.gameHasStarted
                            ? 'The active game has started'
                            : 'If active, has not yet started'),
                        dense: true,
                      ),
                      ListTile(
                        leading: _buildStatusDot(liveGameWatcher.gameHasStarted),
                        title: Text(liveGameWatcher.formatSecondsToMMSS(currentLiveGameTime)),
                        dense: true,
                      ),
                    ],
                  )),
            ),
            const SizedBox(
              height: 10,
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton(
                    onPressed: watcher.clientIsRunning &&
                            socket.isConnected
                        ? () async {
                            try {
                              await httpClient.post('/lol-lobby/v2/lobby',
                                  body: {'queueId': 440});
                            } catch (err) {
                              print(err.toString());
                            }
                          }
                        : null,
                    child: const Text(
                      'CREATE FLEX LOBBY',
                    )),
                ElevatedButton(
                    onPressed: watcher.clientIsRunning &&
                            socket.isConnected
                        ? () async {
                            try {
                              await httpClient.post('/lol-lobby/v2/lobby',
                                  body: {'queueId': 420});
                            } catch (err) {
                              print(err.toString());
                            }
                          }
                        : null,
                    child: const Text(
                      'CREATE SOLO/DUO LOBBY',
                    )),
                ElevatedButton(
                    onPressed: watcher.clientIsRunning &&
                            socket.isConnected &&
                            currentGameflowPhase == 'Lobby'
                        ? () async {
                            try {
                              await httpClient.delete('/lol-lobby/v2/lobby');
                            } catch (err) {
                              print(err.toString());
                            }
                          }
                        : null,
                    child: const Text(
                      'LEAVE LOBBY',
                    )),
              ],
            ),
            const SizedBox(
              height: 10,
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemBuilder: (_, index) {
                  return Text(
                    events[index].toString(),
                    style: TextStyle(
                      fontSize: 12,
                    ),
                  );
                },
                separatorBuilder: (_, __) {
                  return const SizedBox(
                    height: 10,
                  );
                },
                itemCount: events.length,
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDot(bool success) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: success ? Colors.green : Colors.red,
      ),
    );
  }
}
