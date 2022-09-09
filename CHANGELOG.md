## 2.3.2

* Removed cache package and create own cache for LCUHttpClient which is now working bugfree

## 2.2.2

* LCUSocket now also includes wildcard matching for in-between the route
* LCUSocket now includes method to clear all subscriptions
* LCUHttpClient now includes cache expiration durations for each route
* LCUHttpClient now includes match type for each route (equals, contains, startsWith, endsWith)
* LCUHttpClient now includes methods to interact with the cache
* Updated README.md
* Updated example

## 1.2.2+1

* Updated README.md

## 1.2.2

* Bugfix: LCUHttpClient does cache properly now

## 1.2.1

* Firing an event manually in LCUSocket now requires ManualEventResponse instead of EventResponse to differentiate a normal from a manual/test event
* Updated README.md
* Updated example

## 1.1.1

* LCUHttpClient now includes a configurable cache to reduce the requests towards the LCU API
* Updated README.md
* Updated example

## 1.0.1

* Bugfix: LCULiveGameWatcher's gametime is now always ceiled to represent the correct ingame timer

## 1.0.0+1

* Updated README.md
* Updated example
* Added comments/function descriptions
* Updated property names of LCULiveGameWatcher

## 1.0.0

* Added LCULiveGameWatcher
* Changed syntax on how to instantiate all services
* Updated README.md
* Updated example

## 0.0.1+2

* Updated README.md

## 0.0.1+1

* Updated README.md

## 0.0.1

* Initial release
* Added LCUWatcher, LCUSocket, LCUHttpClient