import 'package:moxxmpp/src/jid.dart';
import 'package:moxxmpp/src/namespaces.dart';
import 'package:moxxmpp/src/stanza.dart';
import 'package:moxxmpp/src/stringxml.dart';

/// Which specification carried the invitation.
enum MucInvitationKind {
  /// XEP-0045: the room forwards `<invite/>` inside `muc#user`.
  mediated,

  /// XEP-0249: the inviter sends `jabber:x:conference` directly.
  direct,
}

/// One invitation to join a room.
///
/// [roomJid] and [inviter] are bare. [inviter] is null when a mediated
/// invite omitted `from`.
class MucInvitation {
  const MucInvitation({
    required this.roomJid,
    required this.kind,
    this.inviter,
    this.password = '',
    this.reason = '',
  });

  final JID roomJid;
  final MucInvitationKind kind;
  final JID? inviter;
  final String password;
  final String reason;
}

/// XEP-0045 mediated invite, or null when [message] is not one.
///
/// The room is the message `from`. The inviter is `<invite from='…'/>`,
/// which the room may omit. The password, when present, is a sibling of
/// `<invite/>`, not a child of it.
MucInvitation? parseMediatedMucInvitation(Stanza message) {
  final from = message.from;
  if (from == null || from.isEmpty) return null;

  final mucUser = message.firstTag('x', xmlns: mucUserXmlns);
  final invite = mucUser?.firstTag('invite');
  if (mucUser == null || invite == null) return null;

  final inviterRaw = invite.attributes['from'];
  JID? inviter;
  if (inviterRaw is String && inviterRaw.isNotEmpty) {
    inviter = JID.fromString(inviterRaw).toBare();
  }

  return MucInvitation(
    roomJid: JID.fromString(from).toBare(),
    kind: MucInvitationKind.mediated,
    inviter: inviter,
    password: mucUser.firstTag('password')?.innerText() ?? '',
    reason: invite.firstTag('reason')?.innerText() ?? '',
  );
}

/// XEP-0249 direct invite, or null when [message] is not one.
///
/// `jid` is the room. The message `from` is the person inviting us.
MucInvitation? parseDirectMucInvitation(Stanza message) {
  final from = message.from;
  if (from == null || from.isEmpty) return null;

  final direct = message.firstTag('x', xmlns: directMucInvitationXmlns);
  if (direct == null) return null;
  final roomRaw = direct.attributes['jid'];
  if (roomRaw is! String || roomRaw.isEmpty) return null;

  return MucInvitation(
    roomJid: JID.fromString(roomRaw).toBare(),
    kind: MucInvitationKind.direct,
    inviter: JID.fromString(from).toBare(),
    password: (direct.attributes['password'] as String?) ?? '',
    reason: (direct.attributes['reason'] as String?) ?? '',
  );
}

/// Mediated invite the room will forward (XEP-0045 §7.8.2).
///
/// Sent to the bare room, not to the invitee. The room stamps `from` with
/// the inviter when it relays the stanza.
Stanza mediatedMucInviteMessage({required JID room, required JID invitee}) {
  return Stanza.message(
    to: room.toBare().toString(),
    children: [
      XMLNode.xmlns(
        tag: 'x',
        xmlns: mucUserXmlns,
        children: [
          XMLNode(
            tag: 'invite',
            attributes: {'to': invitee.toBare().toString()},
          ),
        ],
      ),
    ],
  );
}

/// Decline a mediated invite (XEP-0045 §7.8.2).
///
/// [inviter] is the `to` on `<decline/>`: the room delivers the refusal to
/// that occupant. Omit it when the incoming invite did not name anyone.
Stanza mediatedMucDeclineMessage({required JID room, JID? inviter}) {
  final to = inviter?.toBare().toString();
  return Stanza.message(
    to: room.toBare().toString(),
    children: [
      XMLNode.xmlns(
        tag: 'x',
        xmlns: mucUserXmlns,
        children: [
          XMLNode(
            tag: 'decline',
            attributes: {if (to != null && to.isNotEmpty) 'to': to},
          ),
        ],
      ),
    ],
  );
}
