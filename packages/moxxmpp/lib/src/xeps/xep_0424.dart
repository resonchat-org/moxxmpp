import 'package:moxxmpp/src/managers/base.dart';
import 'package:moxxmpp/src/xeps/xep_0425.dart';
import 'package:moxxmpp/src/managers/data.dart';
import 'package:moxxmpp/src/managers/handlers.dart';
import 'package:moxxmpp/src/managers/namespaces.dart';
import 'package:moxxmpp/src/managers/priorities.dart';
import 'package:moxxmpp/src/message.dart';
import 'package:moxxmpp/src/namespaces.dart';
import 'package:moxxmpp/src/stanza.dart';
import 'package:moxxmpp/src/stringxml.dart';
import 'package:moxxmpp/src/util/typed_map.dart';

/// Fallback body from XEP-0424. Supporting clients must not display it.
const messageRetractionFallback =
    "/me retracted a previous message, but it's unsupported by your client.";

/// A retraction request, or a tombstone that replaced an archived message.
class MessageRetractionData implements StanzaHandlerExtension {
  const MessageRetractionData({
    required this.id,
    this.tombstone = false,
    this.stamp,
  });

  /// For a request, the id of the message to retract.
  ///
  /// For a tombstone, the id of the retraction stanza (`<retracted id>`).
  /// The retracted message is the carrier itself.
  final String id;

  /// True when this element is `<retracted/>` standing in for the original.
  final bool tombstone;

  /// When the retraction happened, from a tombstone's `stamp`.
  final DateTime? stamp;

  List<XMLNode> toXML() {
    if (tombstone || id.isEmpty) return const [];
    return messageRetractionNodes(id);
  }
}

/// The elements of a retraction request (XEP-0424 §3).
List<XMLNode> messageRetractionNodes(String targetId) {
  return [
    XMLNode.xmlns(
      tag: 'retract',
      xmlns: messageRetractionXmlns,
      attributes: {'id': targetId},
    ),
    XMLNode.xmlns(
      tag: 'fallback',
      xmlns: fallbackIndicationXmlns,
      attributes: {'for': messageRetractionXmlns},
    ),
    XMLNode(tag: 'body', text: messageRetractionFallback),
    XMLNode.xmlns(tag: 'store', xmlns: messageProcessingHintsXmlns),
  ];
}

class MessageRetractionManager extends XmppManagerBase {
  MessageRetractionManager() : super(messageRetractionManager);

  @override
  List<String> getDiscoFeatures() => [messageRetractionXmlns];

  @override
  List<StanzaHandler> getIncomingStanzaHandlers() => [
    StanzaHandler(
      stanzaTag: 'message',
      callback: _onMessage,
      // Before the MessageManager
      priority: messageExtensionPriority,
    ),
  ];

  @override
  Future<bool> isSupported() async => true;

  Future<StanzaHandlerData> _onMessage(
    Stanza message,
    StanzaHandlerData state,
  ) async {
    final retract = message.firstTag('retract', xmlns: messageRetractionXmlns);
    if (retract != null) {
      // A moderation retract (XEP-0425) is only legitimate from the room.
      // An occupant spoofing `<moderated/>` must not retract anything.
      if (moderatedRetractionIsSpoofed(message)) return state;
      final id = retract.attributes['id'] as String?;
      if (id != null && id.isNotEmpty) {
        return state..extensions.set(MessageRetractionData(id: id));
      }
    }

    final tombstone = message.firstTag(
      'retracted',
      xmlns: messageRetractionXmlns,
    );
    if (tombstone != null) {
      final raw = tombstone.attributes['stamp'] as String?;
      return state
        ..extensions.set(
          MessageRetractionData(
            id: tombstone.attributes['id'] as String? ?? '',
            tombstone: true,
            stamp: raw == null ? null : DateTime.tryParse(raw),
          ),
        );
    }

    return state;
  }

  List<XMLNode> _messageSendingCallback(
    TypedMap<StanzaHandlerExtension> extensions,
  ) {
    return extensions.get<MessageRetractionData>()?.toXML() ?? const [];
  }

  @override
  Future<void> postRegisterCallback() async {
    await super.postRegisterCallback();

    getAttributes()
        .getManagerById<MessageManager>(messageManager)
        ?.registerMessageSendingCallback(_messageSendingCallback);
  }
}
