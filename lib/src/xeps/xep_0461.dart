import 'package:meta/meta.dart';

import 'package:moxxmpp/src/jid.dart';
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

/// A reply to a message.
class ReplyData implements StanzaHandlerExtension {
  const ReplyData(this.id, {this.body, this.jid, this.start, this.end});

  ReplyData.fromQuoteData(this.id, QuoteData quote, {this.jid})
    : body = quote.body,
      start = 0,
      end = quote.fallbackLength;

  /// The JID of the entity whose message we are replying to.
  final JID? jid;

  /// The id of the message that is replied to. What id to use depends on what kind
  /// of message you want to reply to.
  final String id;

  /// The start of the fallback body (inclusive)
  final int? start;

  /// The end of the fallback body (exclusive)
  final int? end;

  /// The (wire) body associated with this reply, when known.
  ///
  /// On receive, this is the message's `<body/>`. On send it is optional
  /// metadata for [withoutFallback] — the stanza body itself must come from
  /// [MessageBodyData], never from this field (Conversations sends one body).
  final String? body;

  /// Applies the metadata to the received body [body] in order to remove the fallback.
  /// If either [ReplyData.start] or [ReplyData.end] are null, then body is returned as
  /// is.
  String? get withoutFallback {
    if (body == null) return null;
    if (start == null || end == null) return body;

    return body!.replaceRange(start!, end, '');
  }
}

/// Internal class describing how to build a message with a quote fallback body.
class QuoteData {
  const QuoteData(this.body, this.fallbackLength);

  /// Takes the body of the message we want to quote [quoteBody] and the content of
  /// the reply [body] and computes the fallback body and its length.
  factory QuoteData.fromBodies(String quoteBody, String body) {
    final fallback = quoteBody.split('\n').map((line) => '> $line\n').join();

    return QuoteData('$fallback$body', fallback.length);
  }

  /// The new body with fallback data at the beginning
  final String body;

  /// The length of the fallback data
  final int fallbackLength;
}

/// A manager implementing support for parsing XEP-0461 metadata. The
/// MessageRepliesManager itself does not modify the body of the message.
class MessageRepliesManager extends XmppManagerBase {
  MessageRepliesManager() : super(messageRepliesManager);

  @override
  List<String> getDiscoFeatures() => [replyXmlns];

  @override
  List<StanzaHandler> getIncomingStanzaHandlers() => [
    StanzaHandler(
      stanzaTag: 'message',
      tagName: 'reply',
      tagXmlns: replyXmlns,
      callback: _onMessage,
      // Before the message handler
      priority: messageExtensionPriority,
    ),
  ];

  @override
  Future<bool> isSupported() async => true;

  @visibleForTesting
  List<XMLNode> messageSendingCallback(
    TypedMap<StanzaHandlerExtension> extensions,
  ) {
    final data = extensions.get<ReplyData>();
    if (data == null) {
      return [];
    }
    // Only <reply> and <fallback>. The message body is owned by
    // MessageBodyData (MessageManager) — emitting another <body/> here
    // duplicated Conversations' single body and broke last-body clients.
    return [
      XMLNode.xmlns(
        tag: 'reply',
        xmlns: replyXmlns,
        attributes: {
          // The to attribute is optional
          if (data.jid != null) 'to': data.jid!.toString(),

          'id': data.id,
        },
      ),
      if (data.start != null && data.end != null)
        XMLNode.xmlns(
          tag: 'fallback',
          xmlns: fallbackIndicationXmlns,
          attributes: {'for': replyXmlns},
          children: [
            XMLNode(
              tag: 'body',
              attributes: {
                'start': data.start!.toString(),
                'end': data.end!.toString(),
              },
            ),
          ],
        ),
    ];
  }

  Future<StanzaHandlerData> _onMessage(
    Stanza stanza,
    StanzaHandlerData state,
  ) async {
    final reply = stanza.firstTag('reply', xmlns: replyXmlns)!;
    final to = reply.attributes['to'] as String?;
    final jid = to != null ? JID.fromString(to) : null;
    int? start;
    int? end;

    // TODO(Unknown): Maybe extend firstTag to also look for attributes
    final fallback = stanza.firstTag(
      'fallback',
      xmlns: fallbackIndicationXmlns,
    );
    if (fallback != null) {
      final body = fallback.firstTag('body')!;
      start = int.parse(body.attributes['start']! as String);
      end = int.parse(body.attributes['end']! as String);
    }

    return state
      ..extensions.set(
        ReplyData(
          reply.attributes['id']! as String,
          jid: jid,
          start: start,
          end: end,
          body: stanza.firstTag('body')?.innerText(),
        ),
      );
  }

  @override
  Future<void> postRegisterCallback() async {
    await super.postRegisterCallback();

    // Register the sending callback
    getAttributes()
        .getManagerById<MessageManager>(messageManager)
        ?.registerMessageSendingCallback(messageSendingCallback);
  }
}
