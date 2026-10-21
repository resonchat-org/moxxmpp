/// TCP transport (RFC 6120 and XEP-0368).
///
/// Kept off the main library because this file imports `dart:io`. The web
/// build imports `package:moxxmpp/moxxmpp.dart` only.
library;

export 'package:moxxmpp/src/socket_tcp/events.dart';
export 'package:moxxmpp/src/socket_tcp/record.dart';
export 'package:moxxmpp/src/socket_tcp/socket.dart';
