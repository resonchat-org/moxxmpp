import 'package:test/test.dart';

import 'package:moxxmpp/src/jid.dart';
import 'package:moxxmpp/src/namespaces.dart';
import 'package:moxxmpp/src/stanza.dart';
import 'package:moxxmpp/src/stringxml.dart';
import 'package:moxxmpp/src/xeps/xep_0045/invitation.dart';

void main() {
  test('parses a mediated muc#user invite', () {
    final stanza = Stanza.message(
      from: 'room@conference.example.org',
      to: 'me@example.org',
      children: [
        XMLNode.xmlns(
          tag: 'x',
          xmlns: mucUserXmlns,
          children: [
            XMLNode(
              tag: 'invite',
              attributes: {'from': 'alice@example.org/phone'},
              children: [XMLNode(tag: 'reason', text: 'join us')],
            ),
            XMLNode(tag: 'password', text: 's3cret'),
          ],
        ),
      ],
    );
    final invite = parseMediatedMucInvitation(stanza)!;
    expect(invite.kind, MucInvitationKind.mediated);
    expect(invite.roomJid.toString(), 'room@conference.example.org');
    expect(invite.inviter.toString(), 'alice@example.org');
    expect(invite.reason, 'join us');
    expect(invite.password, 's3cret');
  });

  test('a muc#user status without invite is not an invitation', () {
    final stanza = Stanza.message(
      from: 'room@conference.example.org/nick',
      type: 'groupchat',
      children: [
        XMLNode(tag: 'body', text: 'hi'),
        XMLNode.xmlns(
          tag: 'x',
          xmlns: mucUserXmlns,
          children: [
            XMLNode(tag: 'status', attributes: {'code': '100'}),
          ],
        ),
      ],
    );
    expect(parseMediatedMucInvitation(stanza), isNull);
  });

  test('invite and decline address the room', () {
    final room = JID.fromString('room@conference.example.org');
    final invitee = JID.fromString('bob@example.org/phone');
    final invite = mediatedMucInviteMessage(room: room, invitee: invitee);
    expect(invite.to, 'room@conference.example.org');
    final x = invite.firstTag('x', xmlns: mucUserXmlns)!;
    expect(x.firstTag('invite')!.attributes['to'], 'bob@example.org');

    final decline = mediatedMucDeclineMessage(
      room: room,
      inviter: JID.fromString('alice@example.org'),
    );
    expect(
      decline
          .firstTag('x', xmlns: mucUserXmlns)!
          .firstTag('decline')!
          .attributes['to'],
      'alice@example.org',
    );
  });
}
