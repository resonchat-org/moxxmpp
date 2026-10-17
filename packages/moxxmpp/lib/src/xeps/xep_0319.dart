import 'package:meta/meta.dart';
import 'package:moxxmpp/src/managers/base.dart';
import 'package:moxxmpp/src/managers/data.dart';
import 'package:moxxmpp/src/managers/handlers.dart';
import 'package:moxxmpp/src/managers/namespaces.dart';
import 'package:moxxmpp/src/managers/priorities.dart';
import 'package:moxxmpp/src/namespaces.dart';
import 'package:moxxmpp/src/stanza.dart';

/// XEP-0319: last user interaction carried on presence.
@immutable
class IdleData implements StanzaHandlerExtension {
  const IdleData(this.since);

  /// `<idle since='…'/>`, when the sender became idle.
  final DateTime since;
}

/// Parses `<idle xmlns='urn:xmpp:idle:1' since='…'/>`. Null when absent or
/// not a timestamp.
DateTime? idleSinceFromStanza(Stanza presence) {
  final idle = presence.firstTag('idle', xmlns: idleXmlns);
  final raw = idle?.attributes['since'];
  if (raw == null) return null;
  final since = raw.toString().trim();
  if (since.isEmpty) return null;
  return DateTime.tryParse(since);
}

class IdleManager extends XmppManagerBase {
  IdleManager() : super(idleManager);

  @override
  Future<bool> isSupported() async => true;

  @override
  List<StanzaHandler> getIncomingStanzaHandlers() => [
    StanzaHandler(
      stanzaTag: 'presence',
      tagName: 'idle',
      tagXmlns: idleXmlns,
      callback: _onIdle,
      // Before PresenceManager marks the stanza done.
      priority: presenceExtensionPriority,
    ),
  ];

  Future<StanzaHandlerData> _onIdle(
    Stanza presence,
    StanzaHandlerData state,
  ) async {
    final since = idleSinceFromStanza(presence);
    if (since == null) return state;
    return state..extensions.set(IdleData(since));
  }
}
