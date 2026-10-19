import 'package:moxxmpp/src/jid.dart';
import 'package:moxxmpp/src/managers/base.dart';
import 'package:moxxmpp/src/managers/data.dart';
import 'package:moxxmpp/src/managers/handlers.dart';
import 'package:moxxmpp/src/managers/namespaces.dart';
import 'package:moxxmpp/src/managers/priorities.dart';
import 'package:moxxmpp/src/namespaces.dart';
import 'package:moxxmpp/src/stanza.dart';
import 'package:moxxmpp/src/stringxml.dart';

/// A moderator retracted someone else's group message (XEP-0425).
///
/// The request is an IQ to the room. The room then broadcasts a groupchat
/// `<retract/>` (XEP-0424) that contains `<moderated/>`, or later replaces
/// the archived message with a tombstone that contains the same element.
class MessageModerationData implements StanzaHandlerExtension {
  const MessageModerationData({
    required this.stanzaId,
    this.by,
    this.nick,
    this.occupantId,
    this.reason,
    this.tombstone = false,
    this.spoofed = false,
  });

  /// A `<retract>` that claims to be a moderation but did not come from the
  /// room. Callers drop the stanza.
  const MessageModerationData.spoofed()
    : stanzaId = '',
      by = null,
      nick = null,
      occupantId = null,
      reason = null,
      tombstone = false,
      spoofed = true;

  /// The room stanza-id of the message being retracted.
  ///
  /// On a tombstone this is the retraction stanza id from `<retracted id>`,
  /// and the retracted message is the carrier itself.
  final String stanzaId;

  /// The `by` JID on `<moderated/>` (room occupant, or a real JID).
  final String? by;

  /// Nickname to show: the resource of [by].
  final String? nick;

  /// XEP-0421 occupant id of the moderator, when the room attached one.
  final String? occupantId;

  /// Optional reason the moderator gave.
  final String? reason;

  /// True when this was read from a `<retracted/>` tombstone.
  final bool tombstone;

  /// True when a moderation `<retract>` arrived from an occupant rather than
  /// from the room. Those stanzas are discarded.
  final bool spoofed;
}

/// True when [message] carries a moderation `<retract>` that must be ignored.
///
/// XEP-0425: only a moderation message from the MUC service itself (the bare
/// room JID, no nickname) is legitimate. A tombstone is not subject to that
/// rule. Anything else that wraps `<moderated/>` inside `<retract/>` is dropped.
bool moderatedRetractionIsSpoofed(Stanza message) {
  final retract = message.firstTag('retract', xmlns: messageRetractionXmlns);
  if (retract == null) return false;
  if (retract.firstTag('moderated', xmlns: messageModerateXmlns) == null) {
    return false;
  }
  if (message.attributes['type'] != 'groupchat') return true;
  final raw = message.attributes['from'] as String?;
  if (raw == null || raw.isEmpty) return true;
  return JID.fromString(raw).resource.isNotEmpty;
}

/// Nickname from a moderation `by` JID. The resource is the room nick.
String? moderatorNick(String? by) {
  if (by == null || by.isEmpty) return null;
  final resource = JID.fromString(by).resource;
  if (resource.isNotEmpty) return resource;
  return by;
}

/// Reads `<moderated/>` from a groupchat retraction or tombstone.
MessageModerationData? parseMessageModeration(Stanza message) {
  if (moderatedRetractionIsSpoofed(message)) {
    return const MessageModerationData.spoofed();
  }
  if (message.attributes['type'] != 'groupchat') return null;

  final retract = message.firstTag('retract', xmlns: messageRetractionXmlns);
  final tombstone = message.firstTag(
    'retracted',
    xmlns: messageRetractionXmlns,
  );
  final carrier = retract ?? tombstone;
  if (carrier == null) return null;
  final moderated = carrier.firstTag('moderated', xmlns: messageModerateXmlns);
  if (moderated == null) return null;

  final by = moderated.attributes['by'] as String?;
  final occupant = moderated.firstTag('occupant-id', xmlns: occupantIdXmlns);
  final reason = carrier.firstTag('reason')?.innerText();
  final id = carrier.attributes['id'] as String? ?? '';
  return MessageModerationData(
    stanzaId: id,
    by: by,
    nick: moderatorNick(by),
    occupantId: occupant?.attributes['id'] as String?,
    reason: (reason == null || reason.isEmpty) ? null : reason,
    tombstone: retract == null,
  );
}

class MessageModerationManager extends XmppManagerBase {
  MessageModerationManager() : super(messageModerationManager);

  @override
  List<StanzaHandler> getIncomingStanzaHandlers() => [
    StanzaHandler(
      stanzaTag: 'message',
      callback: _onMessage,
      // Before the MessageManager, alongside XEP-0424.
      priority: messageExtensionPriority,
    ),
  ];

  @override
  Future<bool> isSupported() async => true;

  Future<StanzaHandlerData> _onMessage(
    Stanza message,
    StanzaHandlerData state,
  ) async {
    final moderation = parseMessageModeration(message);
    if (moderation == null) return state;
    return state..extensions.set(moderation);
  }

  /// Asks [room] to retract the message with stanza-id [stanzaId].
  ///
  /// The room applies it and broadcasts the retraction. [reason] is optional
  /// and is shown by clients that display one; this client does not.
  Future<bool> moderate({
    required JID room,
    required String stanzaId,
    String? reason,
  }) async {
    if (stanzaId.isEmpty) return false;
    final children = <XMLNode>[
      XMLNode.xmlns(tag: 'retract', xmlns: messageRetractionXmlns),
      if (reason != null && reason.isNotEmpty)
        XMLNode(tag: 'reason', text: reason),
    ];
    final result = await getAttributes().sendStanza(
      StanzaDetails(
        Stanza.iq(
          to: room.toBare().toString(),
          type: 'set',
          children: [
            XMLNode.xmlns(
              tag: 'moderate',
              xmlns: messageModerateXmlns,
              attributes: {'id': stanzaId},
              children: children,
            ),
          ],
        ),
        shouldEncrypt: false,
      ),
    );
    return result != null && result.attributes['type'] == 'result';
  }
}
