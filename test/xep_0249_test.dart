import 'package:test/test.dart';

import 'package:moxxmpp/src/namespaces.dart';
import 'package:moxxmpp/src/stanza.dart';
import 'package:moxxmpp/src/stringxml.dart';
import 'package:moxxmpp/src/xeps/xep_0045/invitation.dart';

void main() {
  test('parses a direct jabber:x:conference invite', () {
    final stanza = Stanza.message(
      from: 'bob@example.org/laptop',
      to: 'me@example.org',
      children: [
        XMLNode.xmlns(
          tag: 'x',
          xmlns: directMucInvitationXmlns,
          attributes: {
            'jid': 'party@muc.example.org',
            'password': 'pw',
            'reason': 'party',
          },
        ),
      ],
    );
    final invite = parseDirectMucInvitation(stanza)!;
    expect(invite.kind, MucInvitationKind.direct);
    expect(invite.roomJid.toString(), 'party@muc.example.org');
    expect(invite.inviter.toString(), 'bob@example.org');
    expect(invite.password, 'pw');
    expect(invite.reason, 'party');
  });

  test('ignores ordinary chat messages', () {
    final stanza = Stanza.message(
      from: 'alice@example.org',
      children: [XMLNode(tag: 'body', text: 'hi')],
    );
    expect(parseDirectMucInvitation(stanza), isNull);
    expect(parseMediatedMucInvitation(stanza), isNull);
  });

  test('a direct invite without a room jid is not an invitation', () {
    final stanza = Stanza.message(
      from: 'bob@example.org',
      children: [XMLNode.xmlns(tag: 'x', xmlns: directMucInvitationXmlns)],
    );
    expect(parseDirectMucInvitation(stanza), isNull);
  });
}
