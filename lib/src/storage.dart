import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:gangplank/src/lcu_watcher.dart';

class LCUStorage {
  SecurityContext? securityContext;
  late bool disableLogging;
  LCUCredentials? credentials;
  String gameClientApi = 'https://127.0.0.1:2999/liveclientdata/';

  LCUStorage({this.disableLogging = false}) {
    readCertificate();
  }

  Future<void> readCertificate() async {
    if (securityContext != null) return;

    String cert =
        await rootBundle.loadString('packages/gangplank/assets/riotgames.pem');
    securityContext = SecurityContext();
    securityContext!.setTrustedCertificatesBytes(utf8.encode(cert));
  }
}
