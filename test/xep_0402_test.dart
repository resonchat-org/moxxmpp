import 'package:test/test.dart';

import 'package:moxxmpp/src/namespaces.dart';
import 'package:moxxmpp/src/stringxml.dart';
import 'package:moxxmpp/src/xeps/xep_0402.dart';

void main() {
  group('ConferenceBookmark native XML', () {
    test('round-trips fields', () {
      final original = ConferenceBookmark(
        jid: 'room@conference.example.org',
        name: 'Room',
        nick: 'alice',
        password: 's3cret',
        autoJoin: true,
      );
      final xml = original.toNativeXml();
      expect(xml.attributes['xmlns'], bookmarks2Xmlns);
      expect(xml.attributes['autojoin'], 'true');
      expect(xml.attributes['name'], 'Room');

      final parsed = ConferenceBookmark.fromNativeItem(
        'room@conference.example.org',
        xml,
      );
      expect(parsed, isNotNull);
      expect(parsed!.jid, 'room@conference.example.org');
      expect(parsed.name, 'Room');
      expect(parsed.nick, 'alice');
      expect(parsed.password, 's3cret');
      expect(parsed.autoJoin, isTrue);
    });

    test('preserves extension children', () {
      final original = ConferenceBookmark(
        jid: 'room@conference.example.org',
        extensions: [
          XMLNode(tag: 'foo', attributes: {'xmlns': 'urn:ex'}),
        ],
      );
      final parsed = ConferenceBookmark.fromNativeItem(
        'room@conference.example.org',
        original.toNativeXml(),
      );
      expect(parsed!.extensions, hasLength(1));
      expect(parsed.extensions.single.tag, 'foo');
    });
  });

  group('ConferenceBookmark legacy XML', () {
    test('round-trips via storage conference', () {
      final original = ConferenceBookmark(
        jid: 'room@conference.example.org',
        name: 'Room',
        nick: 'bob',
        autoJoin: true,
      );
      final parsed = ConferenceBookmark.fromLegacyConference(
        original.toLegacyXml(),
      );
      expect(parsed!.jid, 'room@conference.example.org');
      expect(parsed.name, 'Room');
      expect(parsed.nick, 'bob');
      expect(parsed.autoJoin, isTrue);
    });
  });
}
