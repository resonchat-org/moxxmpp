import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'package:moxxmpp/moxxmpp.dart';
import 'helpers/xml.dart';

void main() {
  test('Test stringxml', () {
    final child = XMLNode(tag: 'uwu', attributes: {'strength': 10});
    final stanza = XMLNode.xmlns(
      tag: 'uwu-meter',
      xmlns: 'uwu',
      children: [child],
    );
    expect(
      XMLNode(tag: 'iq', attributes: {'xmlns': 'uwu'}).toXml(),
      "<iq xmlns='uwu' />",
    );
    expect(
      XMLNode.xmlns(
        tag: 'iq',
        xmlns: 'uwu',
        attributes: {'how': 'uwu'},
      ).toXml(),
      "<iq xmlns='uwu' how='uwu' />",
    );
    expect(
      stanza.toXml(),
      "<uwu-meter xmlns='uwu'><uwu strength=10 /></uwu-meter>",
    );

    expect(
      ClientStreamHeaderNonza(JID.fromString('user@uwu.server')).toXml(),
      "<stream:stream xmlns='jabber:client' version='1.0' xmlns:stream='http://etherx.jabber.org/streams' to='uwu.server' from='user@uwu.server' xml:lang='en'>",
    );

    expect(
      XMLNode(tag: 'text', attributes: {}, text: 'hallo').toXml(),
      '<text>hallo</text>',
    );
    expect(
      XMLNode(tag: 'text', attributes: {'world': 'no'}, text: 'hallo').toXml(),
      "<text world='no'>hallo</text>",
    );
    expect(
      XMLNode(tag: 'text', attributes: {}, text: 'hallo').toXml(),
      '<text>hallo</text>',
    );
    expect(
      XMLNode(tag: 'text', attributes: {}, text: 'test').innerText(),
      'test',
    );
  });

  test('Test XmlElement', () {
    expect(
      XMLNode.fromXmlElement(
        XmlDocument.parse("<root owo='uwu' />").firstElementChild!,
      ).toXml(),
      "<root owo='uwu' />",
    );
  });

  test('attribute values and text are escaped', () {
    // Attributes are rendered single-quoted, so an apostrophe used to end the
    // attribute early. Prosody's pubsub node configuration form contains a
    // label like "The node's title", and echoing that form back made the
    // server answer `not-well-formed` and drop the stream. Message bodies hit
    // the same wall with `&` and `<`.
    final node = XMLNode.xmlns(
      tag: 'field',
      xmlns: 'jabber:x:data',
      attributes: {'label': "The node's title & <subtitle>"},
      text: 'a & b < c > d',
    );

    final xml = node.toXml();

    // What matters is that a parser can read it back.
    final parsed = XmlDocument.parse(xml);
    expect(
      parsed.rootElement.getAttribute('label'),
      "The node's title & <subtitle>",
    );
    expect(parsed.rootElement.innerText, 'a & b < c > d');
    expect(xml, isNot(contains("node's")));
  });

  test('escaping leaves ordinary values alone', () {
    expect(
      XMLNode.xmlns(
        tag: 'iq',
        xmlns: 'uwu',
        attributes: {'how': 'uwu'},
      ).toXml(),
      "<iq xmlns='uwu' how='uwu' />",
    );
  });

  test('Test the find functions', () {
    final node1 = XMLNode.fromString(
      '<message><a xmlns="a" /><body>Hallo</body></message>',
    );

    expect(
      compareXMLNodes(
        node1.firstTag('body')!,
        XMLNode.fromString('<body>Hallo</body>'),
      ),
      true,
    );
    expect(
      compareXMLNodes(
        node1.firstTagByXmlns('a')!,
        XMLNode.fromString('<a xmlns="a" />'),
      ),
      true,
    );
  });

  test('Test compareXMLNodes', () {
    final node1 = XMLNode.fromString('''
 <iq type='set' id='0327c373-2e34-46bd-ab7f-1274a6f7095f' to='pubsub.server.example.org' from='testuser@example.org/MU29eEZn' xmlns='jabber:client'>
  <pubsub xmlns='http://jabber.org/protocol/pubsub'>
    <publish node='princely_musings'>
      <item id='current'>
        <test-item  />
      </item>
    </publish>
    <publish-options >
      <x xmlns='jabber:x:data' type='submit'>
        <field var='FORM_TYPE' type='hidden'>
          <value>http://jabber.org/protocol/pubsub#publish-options</value>
        </field>
        <field var='pubsub#max_items'>
          <value>max</value>
        </field>
      </x>
    </publish-options>
  </pubsub>
</iq>
''');
    final node2 = XMLNode.fromString('''
<iq type="set" to="pubsub.server.example.org" id="a">
  <pubsub xmlns='http://jabber.org/protocol/pubsub'>
    <publish node='princely_musings'>
      <item id="current">
        <test-item />
      </item>
    </publish>
    <publish-options>
      <x xmlns='jabber:x:data' type='submit'>
        <field var='FORM_TYPE' type='hidden'>
          <value>http://jabber.org/protocol/pubsub#publish-options</value>
        </field>
        <field var='pubsub#max_items'>
          <value>1</value>
        </field>
      </x>
    </publish-options>
  </pubsub>
</iq>
''');

    expect(compareXMLNodes(node1, node2), false);
  });

  test('a prefixed xmlns still matches the element', () {
    // Room stanza-ids often arrive as xmlns:sid='urn:xmpp:sid:0' with a
    // sid: prefix. Looking up by the namespace, not the prefix, is what
    // makes that id visible.
    final node = XMLNode.fromString(
      "<message xmlns='jabber:client' xmlns:sid='urn:xmpp:sid:0' "
      "from='room@conf.example/nick' type='groupchat'> "
      "<sid:stanza-id id='room-1' by='room@conf.example'/> "
      "<sid:origin-id id='origin-1'/> "
      '</message>',
    );

    final stanzaId = node.firstTag('stanza-id', xmlns: stableIdXmlns);
    expect(stanzaId?.attributes['id'], 'room-1');
    expect(stanzaId?.attributes['by'], 'room@conf.example');
    expect(
      node.firstTag('origin-id', xmlns: stableIdXmlns)?.attributes['id'],
      'origin-1',
    );
  });

  test('an unprefixed element in the same namespace matches too', () {
    final node = XMLNode.fromString(
      "<message xmlns='jabber:client' from='room@conf.example/nick' "
      "type='groupchat'> "
      "<stanza-id xmlns='urn:xmpp:sid:0' id='room-1' by='room@conf.example'/> "
      '</message>',
    );
    expect(
      node.firstTag('stanza-id', xmlns: stableIdXmlns)?.attributes['id'],
      'room-1',
    );
  });

  test('a prefixed tag keeps its qualified name', () {
    final node = XMLNode.fromString(
      "<stream:features xmlns:stream='http://etherx.jabber.org/streams'/>",
    );
    expect(node.tag, 'stream:features');
  });
}
