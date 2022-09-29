import 'dart:async';

import 'package:gangplank/src/lcu_socket.dart';

class LCUSocketDebouncerItem {
  final List<EventResponse> events = [];
  Timer? debounceTimer;

  LCUSocketDebouncerItem(EventResponse response) {
    events.add(response);
  }

  void dispose() {
    events.clear();
    debounceTimer?.cancel();
  }
}

class LCUSocketDebouncerResponse {
  final EventResponse event;
  final int eventsAccumulated;

  LCUSocketDebouncerResponse({
    required this.event,
    this.eventsAccumulated = 0,
  });
}

class LCUSocketDebouncer {
  final StreamController<LCUSocketDebouncerResponse> _controller = StreamController();
  Stream<LCUSocketDebouncerResponse> get onDebounce => _controller.stream;
  final Duration? debounceDuration;

  LCUSocketDebouncer({this.debounceDuration});

  // MAP CONTAINING KEY = URI AND VALUE = LCUSOCKETDEBOUNCERITEM
  final Map<String, LCUSocketDebouncerItem> _events = {};

  void add(EventResponse response) {
    // ADDING A RESPONSE

    if (debounceDuration == null) {
      // DEBOUNCE DURATION WAS NOT GIVEN -> THE USER DOES NOT WANT TO DEBOUNCE
      // SO WE JUST RETURN THE EVENTRESPONSE IMMEDIATLY AND DONT EXECUTE AND DEBOUNCE LOGIC

      _controller.add(LCUSocketDebouncerResponse(
        event: response,
      ));
      return;
    }

    // THE USER SPECIFIED A DEBOUNCE DURATION

    if (!_events.containsKey(response.uri)) {
      // IF THAT EVENT IS NOT YET FOUND, WE WILL ADD IT AND START THE DEBOUNCE TIMER

      // CREATE DEBOUNCER ITEM TO GET A TIMER WE CAN USE

      final debouncerItem = LCUSocketDebouncerItem(response);

      _events[response.uri] = debouncerItem;

      debouncerItem.debounceTimer = Timer.periodic(debounceDuration!, (_) {
        // DEBOUNCER TRIGGERED AFTER DURATION
        // ADD LAST FOUND RESPONSE IN EVENTLIST AND EMIT IT VIA STREAM

        _controller.add(LCUSocketDebouncerResponse(
          event: debouncerItem.events.last,
          eventsAccumulated: debouncerItem.events.length,
        ));

        // DISPOSE THE DEBOUNCERITEM TO DISPOSE EVENTLIST AND TIMER

        debouncerItem.dispose();

        // REMOVE THE KEY FROM MAP SINCE THE DEBOUNCER TRIGGERED

        _events.remove(response.uri);
      });
    } else {
      // EVENT WAS FOUND BY KEY -> WE WILL JUST APPEND THE EVENTRESPONSE TO THE EVENTLIST

      _events[response.uri]!.events.add(response);
    }
  }

  void dispose() {
    _controller.close();
  }
}
