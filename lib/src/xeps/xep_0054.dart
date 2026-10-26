import 'dart:convert';

import 'package:moxlib/moxlib.dart';

import 'package:moxxmpp/src/events.dart';
import 'package:moxxmpp/src/jid.dart';
import 'package:moxxmpp/src/managers/base.dart';
import 'package:moxxmpp/src/managers/data.dart';
import 'package:moxxmpp/src/managers/handlers.dart';
import 'package:moxxmpp/src/managers/namespaces.dart';
import 'package:moxxmpp/src/namespaces.dart';
import 'package:moxxmpp/src/stanza.dart';
import 'package:moxxmpp/src/stringxml.dart';

abstract class VCardError {}

class UnknownVCardError extends VCardError {}

class InvalidVCardError extends VCardError {}

class VCardPhoto {
  const VCardPhoto({this.binval});
  final String? binval;
}

class VCard {
  const VCard({this.nickname, this.url, this.photo});
  final String? nickname;
  final String? url;
  final VCardPhoto? photo;
}

class VCardManager extends XmppManagerBase {
  VCardManager() : super(vcardManager);
  final Map<String, String> _lastHash = {};

  @override
  List<StanzaHandler> getIncomingStanzaHandlers() => [
    StanzaHandler(
      stanzaTag: 'presence',
      tagName: 'x',
      tagXmlns: vCardTempUpdate,
      callback: _onPresence,
    ),
  ];

  @override
  Future<bool> isSupported() async => true;

  /// In case we get the avatar hash some other way.
  void setLastHash(String jid, String hash) {
    _lastHash[jid] = hash;
  }

  /// SHA-1 from the latest XEP-0153 presence for [jid].
  ///
  /// Keyed by the full address presence came from, so an occupant is
  /// `room@server/nick` and not the room. Empty string means `<photo/>`
  /// advertised no image. Null means this address has not advertised yet.
  String? photoHashFor(JID jid) => _lastHash[jid.toString()];

  Future<StanzaHandlerData> _onPresence(
    Stanza presence,
    StanzaHandlerData state,
  ) async {
    final from = presence.from;
    if (from == null || from.isEmpty) return state;
    final x = presence.firstTag('x', xmlns: vCardTempUpdate)!;
    final photo = x.firstTag('photo');
    if (photo == null) return state;
    // XEP-0153 hashes are hex SHA-1; case is not significant.
    final hash = photo.innerText().trim().toLowerCase();
    final jid = JID.fromString(from);
    final key = jid.toString();
    if (_lastHash[key] == hash) return state;
    _lastHash[key] = hash;

    getAttributes().sendEvent(VCardAvatarUpdatedEvent(jid, hash));
    return state;
  }

  VCardPhoto? _parseVCardPhoto(XMLNode? node) {
    if (node == null) return null;

    return VCardPhoto(binval: node.firstTag('BINVAL')?.innerText());
  }

  VCard _parseVCard(XMLNode vcard) {
    final nickname = vcard.firstTag('NICKNAME')?.innerText();
    final url = vcard.firstTag('URL')?.innerText();

    return VCard(
      url: url,
      nickname: nickname,
      photo: _parseVCardPhoto(vcard.firstTag('PHOTO')),
    );
  }

  Future<Result<VCardError, VCard>> requestVCard(JID jid) async {
    // Plain IQ — same as publishPhoto / Conversations. Do not OMEMO-wrap
    // (MUC room vCards and many servers reject encrypted vCard-temp).
    //
    // Address the JID we were given. XEP-0153 occupant avatars are an IQ to
    // `room@server/nick`; baring that asks the room for its own vCard, and
    // every member without a visible real JID is then drawn with the room
    // photo. Contacts and the room itself are already bare when passed.
    // publishPhoto stays bare: a room avatar is published to the room.
    // The awaiter correlates replies on the bare JID plus stanza id, so a
    // full-JID request still completes when the occupant answers.
    final result = (await getAttributes().sendStanza(
      StanzaDetails(
        Stanza.iq(
          to: jid.toString(),
          type: 'get',
          children: [XMLNode.xmlns(tag: 'vCard', xmlns: vCardTempXmlns)],
        ),
        shouldEncrypt: false,
      ),
    ))!;

    if (result.attributes['type'] != 'result') {
      return Result(UnknownVCardError());
    }
    final vcard = result.firstTag('vCard', xmlns: vCardTempXmlns);
    if (vcard == null) {
      return Result(UnknownVCardError());
    }

    return Result(_parseVCard(vcard));
  }

  /// Publish a PHOTO on [address]'s vCard (Conversations `publishPhoto`).
  ///
  /// Used for MUC room avatars (`to=room@conference…`). Merges into an
  /// existing vCard when present; creates a fresh one on item-not-found.
  Future<Result<VCardError, bool>> publishPhoto(
    JID address,
    String type,
    List<int> imageBytes,
  ) async {
    final existing = await _requestVCardNode(address);
    final children = <XMLNode>[];
    if (existing != null) {
      for (final child in existing.children) {
        if (child.tag == 'PHOTO') continue;
        children.add(child);
      }
    }
    children.add(
      XMLNode(
        tag: 'PHOTO',
        children: [
          XMLNode(tag: 'TYPE', text: type),
          XMLNode(tag: 'BINVAL', text: base64Encode(imageBytes)),
        ],
      ),
    );

    final result = (await getAttributes().sendStanza(
      StanzaDetails(
        Stanza.iq(
          to: address.toBare().toString(),
          type: 'set',
          children: [
            XMLNode.xmlns(
              tag: 'vCard',
              xmlns: vCardTempXmlns,
              children: children,
            ),
          ],
        ),
        shouldEncrypt: false,
      ),
    ))!;

    if (result.attributes['type'] != 'result') {
      return Result(UnknownVCardError());
    }
    return const Result(true);
  }

  Future<XMLNode?> _requestVCardNode(JID jid) async {
    final result = await getAttributes().sendStanza(
      StanzaDetails(
        Stanza.iq(
          to: jid.toBare().toString(),
          type: 'get',
          children: [XMLNode.xmlns(tag: 'vCard', xmlns: vCardTempXmlns)],
        ),
        shouldEncrypt: false,
      ),
    );
    if (result == null || result.attributes['type'] != 'result') return null;
    return result.firstTag('vCard', xmlns: vCardTempXmlns);
  }
}
