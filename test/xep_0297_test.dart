import 'package:test/test.dart';

import 'package:moxxmpp/moxxmpp.dart';

void main() {
  group('packForwardedMessage', () {
    test('wraps the original with jabber:client and optional delay', () {
      final original = Stanza.message(
        from: 'alice@capulet.lit/orchard',
        to: 'romeo@montague.lit',
        id: 'orig-1',
        type: 'chat',
        children: [MessageBodyData('hello').toXML()],
      );
      final stamped = DateTime.utc(2010, 7, 10, 23, 8, 25);
      final node = packForwardedMessage(
        original: original,
        receivedAt: stamped,
      );

      expect(node.tag, 'forwarded');
      expect(node.xmlns, forwardedXmlns);
      final delay = node.firstTag('delay', xmlns: delayedDeliveryXmlns);
      expect(delay?.attributes['stamp'], stamped.toIso8601String());
      final inner = node.firstTag('message', xmlns: stanzaXmlns)!;
      expect(inner.attributes['from'], 'alice@capulet.lit/orchard');
      expect(inner.attributes['id'], 'orig-1');
      expect(inner.firstTag('body')?.innerText(), 'hello');
    });
  });

  group('parseUserForwarded', () {
    test('reads a direct forwarded child', () {
      final outer = Stanza.message(
        to: 'mercutio@verona.lit',
        type: 'chat',
        id: 'fwd-1',
        children: [
          MessageBodyData('').toXML(),
          packForwardedMessage(
            original: Stanza.message(
              from: 'juliet@capulet.lit/orchard',
              to: 'romeo@montague.lit',
              id: '0202197',
              type: 'chat',
              children: [
                MessageBodyData(
                  'Yet I should kill thee with much cherishing.',
                ).toXML(),
              ],
            ),
            receivedAt: DateTime.utc(2010, 7, 10, 23, 8, 25),
          ),
        ],
      );

      final data = parseUserForwarded(outer)!;
      expect(data.encrypted, isFalse);
      expect(data.from, 'juliet@capulet.lit/orchard');
      expect(data.type, 'chat');
      expect(data.body, 'Yet I should kill thee with much cherishing.');
      expect(data.delay, DateTime.utc(2010, 7, 10, 23, 8, 25));
    });

    test('returns null when forwarded is not a direct child', () {
      // Carbons shape: <received><forwarded/></received>
      final outer = Stanza.message(
        type: 'chat',
        children: [
          XMLNode.xmlns(
            tag: 'received',
            xmlns: carbonsXmlns,
            children: [
              packForwardedMessage(
                original: Stanza.message(
                  from: 'a@b/c',
                  type: 'chat',
                  children: [MessageBodyData('hid').toXML()],
                ),
              ),
            ],
          ),
        ],
      );
      expect(parseUserForwarded(outer), isNull);
    });

    test('marks an OMEMO inner payload as encrypted', () {
      final outer = Stanza.message(
        type: 'chat',
        children: [
          packForwardedMessage(
            original: Stanza.message(
              from: 'a@b/c',
              type: 'chat',
              children: [XMLNode.xmlns(tag: 'encrypted', xmlns: omemoXmlns)],
            ),
          ),
        ],
      );
      final data = parseUserForwarded(outer)!;
      expect(data.encrypted, isTrue);
      expect(data.body, isEmpty);
    });
  });
}
