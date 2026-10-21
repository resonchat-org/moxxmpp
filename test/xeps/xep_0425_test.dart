import 'package:test/test.dart';

import 'package:moxxmpp/moxxmpp.dart';

Stanza _stanza(String xml) => Stanza.fromXMLNode(XMLNode.fromString(xml));

void main() {
  test(
    'current moderation announcement names the moderator and the reason',
    () {
      // XEP-0425 example 5. The retract id is the room stanza-id.
      final parsed = parseMessageModeration(
        _stanza('''
<message type="groupchat" id="retraction-id-1" from="room@muc.example.com">
  <retract id="stanza-id-1" xmlns="urn:xmpp:message-retract:1">
    <moderated by="room@muc.example.com/macbeth" xmlns="urn:xmpp:message-moderate:1">
      <occupant-id xmlns="urn:xmpp:occupant-id:0" id="dd72603deec90a38ba552f7c68cbcc61bca202cd"/>
    </moderated>
    <reason>This message contains inappropriate content for this forum</reason>
  </retract>
</message>
'''),
      );
      expect(parsed, isNotNull);
      expect(parsed!.spoofed, isFalse);
      expect(parsed.tombstone, isFalse);
      expect(parsed.stanzaId, 'stanza-id-1');
      expect(parsed.nick, 'macbeth');
      expect(
        parsed.reason,
        'This message contains inappropriate content for this forum',
      );
      expect(parsed.occupantId, 'dd72603deec90a38ba552f7c68cbcc61bca202cd');
    },
  );

  test('a moderation with no reason leaves the reason unset', () {
    final parsed = parseMessageModeration(
      _stanza('''
<message type="groupchat" from="room@muc.example.com">
  <retract id="stanza-id-1" xmlns="urn:xmpp:message-retract:1">
    <moderated by="room@muc.example.com/macbeth" xmlns="urn:xmpp:message-moderate:1"/>
  </retract>
</message>
'''),
    );
    expect(parsed!.nick, 'macbeth');
    expect(parsed.reason, isNull);
  });

  test('a fasten announcement from the bare room is a moderation', () {
    // nbxmpp still accepts XEP-0425 0.2. The id lives on apply-to, not on
    // a top-level retract, and the reason lives on moderated.
    final parsed = parseMessageModeration(
      _stanza('''
<message type="groupchat" from="room@muc.example.com">
  <apply-to id="stanza-id-1" xmlns="urn:xmpp:fasten:0">
    <moderated by="room@muc.example.com/macbeth" xmlns="urn:xmpp:message-moderate:0">
      <retract xmlns="urn:xmpp:message-retract:0"/>
      <reason>spam</reason>
    </moderated>
  </apply-to>
</message>
'''),
    );
    expect(parsed!.stanzaId, 'stanza-id-1');
    expect(parsed.nick, 'macbeth');
    expect(parsed.reason, 'spam');
    expect(parsed.tombstone, isFalse);
  });

  test('an occupant fasten announcement is ignored', () {
    final parsed = parseMessageModeration(
      _stanza('''
<message type="groupchat" from="room@muc.example.com/macbeth">
  <apply-to id="stanza-id-1" xmlns="urn:xmpp:fasten:0">
    <moderated by="room@muc.example.com/macbeth" xmlns="urn:xmpp:message-moderate:0">
      <retract xmlns="urn:xmpp:message-retract:0"/>
    </moderated>
  </apply-to>
</message>
'''),
    );
    expect(parsed, isNull);
  });

  test('a moderated retract from an occupant is spoofed', () {
    final parsed = parseMessageModeration(
      _stanza('''
<message type="groupchat" from="room@muc.example.com/macbeth">
  <retract id="stanza-id-1" xmlns="urn:xmpp:message-retract:1">
    <moderated by="room@muc.example.com/macbeth" xmlns="urn:xmpp:message-moderate:1"/>
  </retract>
</message>
'''),
    );
    expect(parsed!.spoofed, isTrue);
  });

  test('a tombstone keeps the moderator and the reason', () {
    final parsed = parseMessageModeration(
      _stanza('''
<message type="groupchat" from="room@muc.example.com/oldhag" id="message-id-1">
  <retracted stamp="2019-09-20T23:19:12Z" xmlns="urn:xmpp:message-retract:1">
    <moderated by="room@muc.example.com/macbeth" xmlns="urn:xmpp:message-moderate:1"/>
    <reason>spam</reason>
  </retracted>
</message>
'''),
      mam: true,
    );
    expect(parsed!.tombstone, isTrue);
    expect(parsed.nick, 'macbeth');
    expect(parsed.reason, 'spam');
  });
}
