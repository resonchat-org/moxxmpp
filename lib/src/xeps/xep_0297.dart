import 'package:meta/meta.dart';

import 'package:moxxmpp/src/managers/base.dart';
import 'package:moxxmpp/src/managers/data.dart';
import 'package:moxxmpp/src/managers/handlers.dart';
import 'package:moxxmpp/src/managers/namespaces.dart';
import 'package:moxxmpp/src/managers/priorities.dart';
import 'package:moxxmpp/src/message.dart';
import 'package:moxxmpp/src/namespaces.dart';
import 'package:moxxmpp/src/stanza.dart';
import 'package:moxxmpp/src/stringxml.dart';
import 'package:moxxmpp/src/util/typed_map.dart';

/// Extracts the message stanza from the <forwarded /> node.
///
/// Used by Carbons / MAM where `<forwarded/>` is nested under another
/// protocol element. User-facing forwards use [parseUserForwarded] /
/// [UserForwardedData] instead.
Stanza unpackForwarded(XMLNode forwarded) {
  assert(
    forwarded.attributes['xmlns'] == forwardedXmlns,
    'Invalid element xmlns',
  );
  assert(forwarded.tag == 'forwarded', 'Invalid element name');

  final stanza = forwarded.firstTag('message', xmlns: stanzaXmlns)!;
  return Stanza(
    to: stanza.attributes['to']! as String,
    from: stanza.attributes['from']! as String,
    type: stanza.attributes['type']! as String,
    id: stanza.attributes['id']! as String,
    tag: stanza.tag,
    attributes: stanza.attributes as Map<String, String>,
    children: stanza.children,
  );
}

/// A user-facing XEP-0297 forward (direct child of `<message/>`, not Carbons/MAM).
@immutable
class UserForwardedData implements StanzaHandlerExtension {
  const UserForwardedData({
    required this.body,
    required this.encrypted,
    this.from,
    this.to,
    this.id,
    this.type,
    this.delay,
  });

  /// Inner message `from` (full or bare).
  final String? from;

  /// Inner message `to`.
  final String? to;

  /// Inner message id.
  final String? id;

  /// Inner `type` (`chat`, `groupchat`, …).
  final String? type;

  /// Plaintext `<body/>` of the inner message (empty when [encrypted]).
  final String body;

  /// When the forwarder received the original (XEP-0203 on `<forwarded/>`).
  final DateTime? delay;

  /// True when the inner stanza carries OMEMO / EME ciphertext — not a
  /// displayable plaintext forward.
  final bool encrypted;
}

/// Builds `<forwarded xmlns='urn:xmpp:forward:0'>` for a user forward.
///
/// Preserves `jabber:client` on the inner message (XEP-0297 §3.2). Optional
/// [receivedAt] becomes a delay stamp on the wrapper.
XMLNode packForwardedMessage({required Stanza original, DateTime? receivedAt}) {
  final attrs = <String, String>{
    'xmlns': stanzaXmlns,
    if (original.from != null) 'from': original.from!,
    if (original.to != null) 'to': original.to!,
    if (original.id != null) 'id': original.id!,
    if (original.type != null) 'type': original.type!,
  };
  final inner = XMLNode(
    tag: 'message',
    attributes: attrs,
    children: List<XMLNode>.from(original.children),
  );
  return XMLNode.xmlns(
    tag: 'forwarded',
    xmlns: forwardedXmlns,
    children: [
      if (receivedAt != null)
        XMLNode.xmlns(
          tag: 'delay',
          xmlns: delayedDeliveryXmlns,
          attributes: {'stamp': receivedAt.toUtc().toIso8601String()},
        ),
      inner,
    ],
  );
}

/// Parses a **user** forward: `<forwarded/>` as a direct child of [outer].
///
/// Returns null when there is no direct forwarded child (Carbons/MAM nest
/// theirs under another element, so they do not match). [UserForwardedData.encrypted]
/// is true when the inner message has an OMEMO/EME encrypted payload.
UserForwardedData? parseUserForwarded(Stanza outer) {
  final forwarded = outer.firstTag('forwarded', xmlns: forwardedXmlns);
  if (forwarded == null) return null;

  final delayNode = forwarded.firstTag('delay', xmlns: delayedDeliveryXmlns);
  DateTime? delay;
  final stamp = delayNode?.attributes['stamp'] as String?;
  if (stamp != null && stamp.isNotEmpty) {
    delay = DateTime.tryParse(stamp);
  }

  final inner =
      forwarded.firstTag('message', xmlns: stanzaXmlns) ??
      forwarded.firstTag('message');
  if (inner == null) return null;

  final encrypted = _innerLooksEncrypted(inner);
  final body = encrypted ? '' : (inner.firstTag('body')?.innerText() ?? '');

  return UserForwardedData(
    from: inner.attributes['from'] as String?,
    to: inner.attributes['to'] as String?,
    id: inner.attributes['id'] as String?,
    type: inner.attributes['type'] as String?,
    body: body,
    delay: delay,
    encrypted: encrypted,
  );
}

bool _innerLooksEncrypted(XMLNode inner) {
  for (final child in inner.children) {
    final ns = child.xmlns;
    if (ns == null) continue;
    if (ns == omemoXmlns ||
        ns == emeOmemo1 ||
        ns == emeOmemo2 ||
        ns.startsWith('eu.siacs.conversations.axolotl') ||
        ns.contains('omemo')) {
      if (child.tag == 'encrypted' || child.tag == 'encryption') return true;
    }
    if (child.tag == 'encrypted' &&
        (ns.contains('omemo') || ns.contains('axolotl'))) {
      return true;
    }
  }
  // EME alone without a body often means ciphertext was stripped/unreadable.
  final eme = inner.firstTag('encryption', xmlns: emeXmlns);
  if (eme != null) {
    final body = inner.firstTag('body')?.innerText() ?? '';
    if (body.isEmpty) return true;
  }
  return false;
}

/// XEP-0297 user-forward parse/send for messages that are not Carbons/MAM.
class StanzaForwardingManager extends XmppManagerBase {
  StanzaForwardingManager() : super(stanzaForwardingManager);

  @override
  List<String> getDiscoFeatures() => [forwardedXmlns];

  @override
  List<StanzaHandler> getIncomingStanzaHandlers() => [
    StanzaHandler(
      stanzaTag: 'message',
      tagName: 'forwarded',
      tagXmlns: forwardedXmlns,
      callback: _onMessage,
      priority: messageExtensionPriority,
    ),
  ];

  @override
  Future<bool> isSupported() async => true;

  Future<StanzaHandlerData> _onMessage(
    Stanza stanza,
    StanzaHandlerData state,
  ) async {
    final data = parseUserForwarded(stanza);
    if (data == null) return state;
    return state..extensions.set(data);
  }

  @visibleForTesting
  List<XMLNode> messageSendingCallback(
    TypedMap<StanzaHandlerExtension> extensions,
  ) {
    final data = extensions.get<UserForwardedData>();
    if (data == null) return [];
    // Rebuild a minimal inner stanza from the typed data for send.
    final original = Stanza.message(
      from: data.from,
      to: data.to,
      id: data.id,
      type: data.type,
      xmlns: stanzaXmlns,
      children: [if (data.body.isNotEmpty) MessageBodyData(data.body).toXML()],
    );
    return [packForwardedMessage(original: original, receivedAt: data.delay)];
  }

  @override
  Future<void> postRegisterCallback() async {
    await super.postRegisterCallback();
    getAttributes()
        .getManagerById<MessageManager>(messageManager)
        ?.registerMessageSendingCallback(messageSendingCallback);
  }
}
