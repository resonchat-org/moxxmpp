import 'package:moxxmpp/src/managers/base.dart';
import 'package:moxxmpp/src/managers/data.dart';
import 'package:moxxmpp/src/managers/handlers.dart';
import 'package:moxxmpp/src/managers/namespaces.dart';
import 'package:moxxmpp/src/managers/priorities.dart';
import 'package:moxxmpp/src/namespaces.dart';
import 'package:moxxmpp/src/stanza.dart';
import 'package:moxxmpp/src/xeps/xep_0045/events.dart';
import 'package:moxxmpp/src/xeps/xep_0045/invitation.dart';

/// XEP-0249 direct MUC invitations (`jabber:x:conference`).
///
/// Mediated invites (the room relays `<invite/>`) are handled by
/// MUCManager. This manager only sees the form the inviter sends straight
/// to us. Either way the stanza is consumed: it is the invitation, and a
/// message pipeline would store it as an empty bubble.
class DirectMucInvitationManager extends XmppManagerBase {
  DirectMucInvitationManager() : super(directMucInvitationManager);

  @override
  Future<bool> isSupported() async => true;

  @override
  List<String> getDiscoFeatures() => [directMucInvitationXmlns];

  @override
  List<StanzaHandler> getIncomingStanzaHandlers() => [
    StanzaHandler(
      stanzaTag: 'message',
      tagName: 'x',
      tagXmlns: directMucInvitationXmlns,
      callback: _onMessage,
      priority: messageExtensionPriority,
    ),
  ];

  Future<StanzaHandlerData> _onMessage(
    Stanza message,
    StanzaHandlerData state,
  ) async {
    final invitation = parseDirectMucInvitation(message);
    if (invitation == null) return state;
    getAttributes().sendEvent(MucInvitationReceivedEvent(invitation));
    return StanzaHandlerData(true, false, message, state.extensions);
  }
}
