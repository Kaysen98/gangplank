## 1.2.2

* Bugfix: LCUHttpClient does cache properly now

## 1.2.1

* Firing an event manually in LCUSocket now requires ManualEventResponse instead of EventResponse to differentiate a normal from a manual/test event. 
* Updated README.md
* Updated example

## 1.1.1

* LCUHttpClient now includes a configurable cache to reduce the requests towards the LCU API.
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