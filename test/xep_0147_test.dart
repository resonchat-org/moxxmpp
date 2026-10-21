import 'package:test/test.dart';

import 'package:moxxmpp/src/xeps/xep_0147.dart';

void main() {
  group('XmppUri (XEP-0147)', () {
    test('join querytype', () {
      final u = XmppUri.tryParse('xmpp:romeo@montague.net?join');
      expect(u, isNotNull);
      expect(u!.jid.toString(), 'romeo@montague.net');
      expect(u.hasQuery, isTrue);
      expect(u.querytype, 'join');
      expect(u.knownQuerytype, XmppUriQuerytype.join);
    });

    test('message with body and subject', () {
      final u = XmppUri.tryParse(
        'xmpp:romeo@montague.net?message;subject=Hello%20World;body=Hi',
      );
      expect(u, isNotNull);
      expect(u!.querytype, 'message');
      expect(u.subject, 'Hello World');
      expect(u.body, 'Hi');
      expect(u.knownQuerytype, XmppUriQuerytype.message);
    });

    test('roster', () {
      final u = XmppUri.tryParse('xmpp:romeo@montague.net?roster;name=Romeo');
      expect(u!.knownQuerytype, XmppUriQuerytype.roster);
      expect(u.name, 'Romeo');
    });

    test('plain jid has no query', () {
      final u = XmppUri.tryParse('xmpp:juliet@capulet.lit');
      expect(u, isNotNull);
      expect(u!.hasQuery, isFalse);
      expect(u.knownQuerytype, XmppUriQuerytype.none);
    });

    test('percent-encoded localpart', () {
      final u = XmppUri.tryParse('xmpp:aD%C3%BCrst@asd.at');
      expect(u!.jid.local, 'aDürst');
    });

    test('rejects authority form', () {
      expect(XmppUri.tryParse('xmpp://romeo@montague.net'), isNull);
    });

    test('rejects non-xmpp', () {
      expect(XmppUri.tryParse('https://example.com'), isNull);
    });

    test('unknown querytype is parseable but not known', () {
      final u = XmppUri.tryParse('xmpp:a@b.example?vcard');
      expect(u!.hasQuery, isTrue);
      expect(u.querytype, 'vcard');
      expect(u.knownQuerytype, isNull);
    });
  });
}
