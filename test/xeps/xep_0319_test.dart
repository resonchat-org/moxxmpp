import 'package:test/test.dart';

import 'package:moxxmpp/src/namespaces.dart';
import 'package:moxxmpp/src/stanza.dart';
import 'package:moxxmpp/src/stringxml.dart';
import 'package:moxxmpp/src/xeps/xep_0319.dart';

void main() {
  test('since parses, and a bad value does not', () {
    final stanza = Stanza.presence(
      from: 'romeo@montague.lit/balcony',
      children: [
        XMLNode.xmlns(
          tag: 'idle',
          xmlns: idleXmlns,
          attributes: {'since': '2026-01-02T03:04:05Z'},
        ),
      ],
    );
    expect(idleSinceFromStanza(stanza), DateTime.utc(2026, 1, 2, 3, 4, 5));

    final broken = Stanza.presence(
      from: 'romeo@montague.lit/balcony',
      children: [
        XMLNode.xmlns(
          tag: 'idle',
          xmlns: idleXmlns,
          attributes: {'since': 'not-a-time'},
        ),
      ],
    );
    expect(idleSinceFromStanza(broken), isNull);
    expect(
      idleSinceFromStanza(Stanza.presence(from: 'romeo@montague.lit/balcony')),
      isNull,
    );
  });
}
