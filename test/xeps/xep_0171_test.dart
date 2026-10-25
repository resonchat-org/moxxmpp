import 'package:test/test.dart';

import 'package:moxxmpp/moxxmpp.dart';

void main() {
  test('language tags match on the primary subtag', () {
    expect(xmppLanguageTagsMatch('zh-Hans', 'zh_CN'), isTrue);
    expect(xmppLanguageTagsMatch('EN', 'en'), isTrue);
    expect(xmppLanguageTagsMatch('en', 'fr'), isFalse);
  });

  test('parses example 1 and keeps the source body', () {
    final stanza = XMLNode.fromString('''
<message xml:lang='en'>
  <body xml:lang='en'>How are you?</body>
  <body xml:lang='fr'>comment allez-vous?</body>
  <x xmlns='urn:xmpp:langtrans'>
    <translation destination_lang='fr' source_lang='en'/>
  </x>
</message>
''');

    final parsed = LangTransData.fromStanza(stanza);
    expect(parsed, isNotNull);
    expect(parsed!.sourceBody, 'How are you?');
    expect(parsed.sourceLang, 'en');
    expect(parsed.translations, hasLength(1));
    expect(parsed.translations.single.destinationLang, 'fr');
    expect(parsed.translations.single.text, 'comment allez-vous?');
    expect(parsed.translations.single.engine, isNull);
  });

  test('a destination body listed first is not the source', () {
    final stanza = XMLNode.fromString('''
<message>
  <body xml:lang='fr'>bonjour</body>
  <body xml:lang='en'>hello</body>
  <x xmlns='urn:xmpp:langtrans'>
    <translation destination_lang='fr' source_lang='en' engine='libretranslate'/>
  </x>
</message>
''');

    final parsed = LangTransData.fromStanza(stanza)!;
    expect(parsed.sourceBody, 'hello');
    expect(parsed.sourceLang, 'en');
    expect(parsed.translations.single.text, 'bonjour');
    expect(parsed.translations.single.engine, 'libretranslate');
  });

  test('no langtrans element parses as nothing', () {
    final stanza = XMLNode.fromString('<message><body>hi</body></message>');
    expect(LangTransData.fromStanza(stanza), isNull);
  });

  test('builds a translation request', () {
    final node = translationRequestElement(
      text: 'How are you?',
      sourceLang: 'en',
      destinationLang: 'fr',
      dictionary: 'medical',
    );
    expect(node.tag, 'x');
    expect(node.attributes['xmlns'], langtransXmlns);
    final source = node.firstTag('source')!;
    expect(source.attributes['xml:lang'], 'en');
    expect(source.innerText(), 'How are you?');
    final translation = node.firstTag('translation')!;
    expect(translation.innerText(), isEmpty);
    expect(translation.attributes['destination_lang'], 'fr');
    expect(translation.attributes['dictionary'], 'medical');
  });

  test('parses the translation element text, not a body', () {
    final stanza = XMLNode.fromString('''
<iq type='result' id='translationReq_2' from='translation.shakespeare.lit'>
  <x xmlns='urn:xmpp:langtrans'>
    <source xml:lang='en'>hello, how are you?</source>
    <translation destination_lang='fr' source_lang='en' engine='default'>comment allez-vous?</translation>
  </x>
</iq>
''');

    final parsed = TranslationResponse.fromStanza(stanza)!;
    expect(parsed.sourceLang, 'en');
    expect(parsed.sourceText, 'hello, how are you?');
    expect(parsed.translations.single.destinationLang, 'fr');
    expect(parsed.translations.single.text, 'comment allez-vous?');
    expect(parsed.translations.single.engine, 'default');
    expect(stanza.findTags('body'), isEmpty);
  });

  test('parses language pairs from items', () {
    final query = XMLNode.fromString('''
<query xmlns='urn:xmpp:langtrans:items'>
  <item source_lang='en' jid='translation.shakespeare.lit' destination_lang='fr'
        engine='SYSTRANS 2005 Release 2' pivotable='true'/>
  <item source_lang='en' jid='translation.shakespeare.lit' destination_lang='ru'
        engine='SYSTRANS 2005 Release 2' pivotable='true' dictionary='medical'/>
</query>
''');

    final pairs = TranslationLanguagePair.fromQuery(query);
    expect(pairs, hasLength(2));
    expect(pairs.first.destinationLang, 'fr');
    expect(pairs.first.pivotable, isTrue);
    expect(pairs.first.jid, 'translation.shakespeare.lit');
    expect(pairs.last.dictionary, 'medical');
    expect(pairs.last.pivotable, isTrue);
  });
}
