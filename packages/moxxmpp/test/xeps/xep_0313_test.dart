import 'package:moxxmpp/moxxmpp.dart';
import 'package:test/test.dart';

import '../helpers/manager.dart';

/// Fallback body left on the wire when OMEMO encrypts (Conversations / moxxmpp).
const _axolotlFallback =
    "I sent you an OMEMO encrypted message but your client doesn't seem to "
    'support that. Find more information on https://conversations.im/omemo';

void main() {
  test('MAM unwrap is a pre-handler ahead of OMEMO/PQ decrypt', () {
    // Regression: post-handler unwrap (-98) ran after decrypt (0 / 200), so
    // archive pulls stored the cleartext fallback as the message body.
    final mam = MessageArchiveManagementManager();
    expect(mam.getIncomingStanzaHandlers(), isEmpty);
    final pre = mam.getIncomingPreStanzaHandlers();
    expect(pre, hasLength(1));
    expect(pre.single.priority, stanzaUnwrapPriority);
    expect(pre.single.priority, greaterThan(pqDecryptPriority));
    expect(pre.single.priority, greaterThan(omemoIncomingDecryptPriority));
  });

  test('carbons unwrap shares the same pre-decrypt priority', () {
    final carbons = CarbonsManager();
    final pre = carbons.getIncomingPreStanzaHandlers();
    expect(pre, isNotEmpty);
    for (final h in pre) {
      expect(h.priority, stanzaUnwrapPriority);
    }
  });

  test('MAM-wrapped encrypted stanza is visible to a later decrypt handler', () async {
    // Mirrors monocles MessageParser: unwrap <result/>, then see <encrypted/>.
    final holder = TestingManagerHolder();
    final mam = MessageArchiveManagementManager();
    await holder.register([mam]);

    const queryId = 'q-1';
    final archive = TestingManagerHolder.jid.toBare();
    await mam.registerPendingQueryForTest(archive, queryId);

    // Build from wire XML so the inner <message xmlns='jabber:client'/> matches
    // what servers put in MAM forwards (Stanza.message() omits xmlns by default).
    final wrapper = Stanza.fromXMLNode(
      XMLNode.fromString('''
<message from="${archive}" xmlns="jabber:client">
  <result xmlns="$mamXmlns" queryid="$queryId" id="archive-1">
    <forwarded xmlns="$forwardedXmlns">
      <delay xmlns="$delayedDeliveryXmlns" stamp="2024-01-01T00:00:00Z"/>
      <message xmlns="jabber:client"
               from="alice@example.org/phone"
               to="${archive}"
               id="inner-1"
               type="chat">
        <body>$_axolotlFallback</body>
        <encrypted xmlns="$emeOmemo">
          <header sid="1">
            <key rid="2">YQ==</key>
            <iv>YQ==</iv>
          </header>
          <payload>YQ==</payload>
        </encrypted>
      </message>
    </forwarded>
  </result>
</message>'''),
    );
    final mamHandler = mam.getIncomingPreStanzaHandlers().single;
    var sawEncrypted = false;
    final decryptHandler = StanzaHandler(
      stanzaTag: 'message',
      tagName: 'encrypted',
      tagXmlns: emeOmemo,
      priority: 0,
      callback: (stanza, state) async {
        sawEncrypted = true;
        // Replace fallback the way OmemoManager would after a successful decrypt.
        final kept = stanza.children.where((c) => c.tag != 'body').toList();
        return state
          ..encrypted = true
          ..stanza = stanza.copyWith(
            children: [
              XMLNode(tag: 'body', text: 'secret from archive'),
              ...kept.where(
                (c) =>
                    !(c.tag == 'encrypted' &&
                        c.attributes['xmlns'] == emeOmemo),
              ),
            ],
          );
      },
    );

    // Highest priority first — same sort as XmppConnection.registerManagers.
    final handlers = [mamHandler, decryptHandler]
      ..sort(stanzaHandlerSortComparator);

    var state = StanzaHandlerData(
      false,
      false,
      wrapper,
      TypedMap<StanzaHandlerExtension>(),
    );
    for (final handler in handlers) {
      if (handler.matches(state.stanza)) {
        state = await handler.callback(state.stanza, state);
      }
    }

    expect(
      sawEncrypted,
      isTrue,
      reason: 'decrypt must run on unwrapped stanza',
    );
    expect(state.extensions.get<MAMData>()?.archiveId, 'archive-1');
    expect(state.encrypted, isTrue);
    expect(state.stanza.firstTag('body')?.innerText(), 'secret from archive');
    expect(state.stanza.toXml(), isNot(contains(_axolotlFallback)));
  });
}
