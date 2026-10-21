import 'package:moxxmpp/src/jid.dart';
import 'package:moxxmpp/src/managers/base.dart';
import 'package:moxxmpp/src/managers/data.dart';
import 'package:moxxmpp/src/managers/handlers.dart';
import 'package:moxxmpp/src/managers/namespaces.dart';
import 'package:moxxmpp/src/managers/priorities.dart';
import 'package:moxxmpp/src/namespaces.dart';
import 'package:moxxmpp/src/stanza.dart';
import 'package:moxxmpp/src/stringxml.dart';
import 'package:moxxmpp/src/xeps/xep_0313.dart';

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

/// Direct-child `<reason/>` text. Empty and whitespace-only reasons are absent.
String? _moderationReason(XMLNode parent) {
  final text = parent.firstTag('reason')?.innerText().trim() ?? '';
  if (text.isEmpty) return null;
  return text;
}

XMLNode? _tagEither(XMLNode parent, String tag, String xmlnsA, String xmlnsB) {
  return parent.firstTag(tag, xmlns: xmlnsA) ??
      parent.firstTag(tag, xmlns: xmlnsB);
}

MessageModerationData _moderatedData({
  required XMLNode moderated,
  required String stanzaId,
  required bool tombstone,
  String? reason,
}) {
  final by = moderated.attributes['by'] as String?;
  final occupant = moderated.firstTag('occupant-id', xmlns: occupantIdXmlns);
  return MessageModerationData(
    stanzaId: stanzaId,
    by: by,
    nick: moderatorNick(by),
    occupantId: occupant?.attributes['id'] as String?,
    // nbxmpp reads the reason on the retract for the current XEP, and on
    // `<moderated/>` for the older fasten form. Callers pass whichever they
    // found. An empty reason stays null so the UI can omit it entirely.
    reason: reason ?? _moderationReason(moderated),
    tombstone: tombstone,
  );
}

/// Current XEP-0425: `<moderated/>` wrapped by `<retract/>` or `<retracted/>`.
MessageModerationData? _parseModerationV1(Stanza message) {
  final retract = _tagEither(
    message,
    'retract',
    messageRetractionXmlns,
    messageRetractionV0Xmlns,
  );
  final tombstone = retract == null
      ? _tagEither(
          message,
          'retracted',
          messageRetractionXmlns,
          messageRetractionV0Xmlns,
        )
      : null;
  final carrier = retract ?? tombstone;
  if (carrier == null) return null;
  final moderated = carrier.firstTag('moderated', xmlns: messageModerateXmlns);
  if (moderated == null) return null;
  return _moderatedData(
    moderated: moderated,
    stanzaId: carrier.attributes['id'] as String? ?? '',
    tombstone: retract == null,
    // Spec example 5: `<reason/>` is a sibling of `<moderated/>`.
    reason: _moderationReason(carrier),
  );
}

/// XEP-0425 0.2, still parsed by nbxmpp: a fasten `<apply-to id='stanza-id'/>`
/// from the bare room JID, with `<moderated by='…'/>` inside it.
MessageModerationData? _parseModerationFasten(Stanza message) {
  final raw = message.attributes['from'] as String?;
  if (raw == null || raw.isEmpty) return null;
  // nbxmpp drops a fasten announcement that is not from the bare room.
  if (JID.fromString(raw).resource.isNotEmpty) return null;
  final applyTo = message.firstTag('apply-to', xmlns: fastenXmlns);
  if (applyTo == null) return null;
  final moderated = applyTo.firstTag(
    'moderated',
    xmlns: messageModerateV0Xmlns,
  );
  if (moderated == null) return null;
  final stanzaId = applyTo.attributes['id'] as String? ?? '';
  if (stanzaId.isEmpty) return null;
  final retract = _tagEither(
    moderated,
    'retract',
    messageRetractionV0Xmlns,
    messageRetractionXmlns,
  );
  if (retract == null) return null;
  return _moderatedData(
    moderated: moderated,
    stanzaId: stanzaId,
    tombstone: false,
    reason: _moderationReason(moderated),
  );
}

/// Older MAM tombstone: `<moderated/>` is the direct child, and it wraps
/// `<retracted/>`. nbxmpp only accepts this on an archived message.
MessageModerationData? _parseModerationV0Tombstone(Stanza message) {
  final moderated = message.firstTag(
    'moderated',
    xmlns: messageModerateV0Xmlns,
  );
  if (moderated == null) return null;
  final retracted = _tagEither(
    moderated,
    'retracted',
    messageRetractionV0Xmlns,
    messageRetractionXmlns,
  );
  if (retracted == null) return null;
  return _moderatedData(
    moderated: moderated,
    stanzaId: '',
    tombstone: true,
    reason: _moderationReason(moderated),
  );
}

/// Reads a groupchat moderation the way nbxmpp does.
///
/// [mam] is true once the stanza has been unwrapped from a MAM result. The
/// older tombstone shape is only legitimate there.
MessageModerationData? parseMessageModeration(
  Stanza message, {
  bool mam = false,
}) {
  if (moderatedRetractionIsSpoofed(message)) {
    return const MessageModerationData.spoofed();
  }
  if (message.attributes['type'] != 'groupchat') return null;

  final current = _parseModerationV1(message);
  if (current != null) return current;
  final fastened = _parseModerationFasten(message);
  if (fastened != null) return fastened;
  if (!mam) return null;
  return _parseModerationV0Tombstone(message);
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
    final moderation = parseMessageModeration(
      message,
      mam: state.extensions.get<MAMData>() != null,
    );
    if (moderation == null) return state;
    return state..extensions.set(moderation);
  }

  /// Asks [room] to retract the message with stanza-id [stanzaId].
  ///
  /// The room applies it and broadcasts the retraction. [reason] is optional.
  /// The broadcast carries it next to `<moderated/>` when the moderator gave
  /// one; an empty reason is omitted from the IQ.
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
