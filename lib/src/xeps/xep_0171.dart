import 'package:moxlib/moxlib.dart';

import 'package:moxxmpp/src/jid.dart';
import 'package:moxxmpp/src/managers/base.dart';
import 'package:moxxmpp/src/managers/data.dart';
import 'package:moxxmpp/src/managers/handlers.dart';
import 'package:moxxmpp/src/managers/namespaces.dart';
import 'package:moxxmpp/src/managers/priorities.dart';
import 'package:moxxmpp/src/message.dart';
import 'package:moxxmpp/src/namespaces.dart';
import 'package:moxxmpp/src/stanza.dart';
import 'package:moxxmpp/src/stringxml.dart';

/// Primary language subtag of [tag] (`zh-Hans` → `zh`), lowercased.
///
/// RFC 5646 tags are compared case-insensitively. Regional variants of the
/// same language match; this does not treat `zh` and `yue` as the same.
String xmppLanguagePrimary(String tag) {
  final trimmed = tag.trim().toLowerCase().replaceAll('_', '-');
  if (trimmed.isEmpty) return '';
  return trimmed.split('-').first;
}

/// Whether [a] and [b] are the same language for XEP-0171 body selection.
bool xmppLanguageTagsMatch(String a, String b) {
  final left = xmppLanguagePrimary(a);
  final right = xmppLanguagePrimary(b);
  return left.isNotEmpty && left == right;
}

/// One translation a remote entity already wrote onto a message.
///
/// The text lives in the `<body xml:lang='destination_lang'>`, not in the
/// `<translation/>` hint. This client does not write these elements.
class LanguageTranslation {
  const LanguageTranslation({
    required this.destinationLang,
    required this.text,
    this.sourceLang,
    this.engine,
    this.dictionary,
    this.charset,
    this.reviewed = false,
  });

  /// `destination_lang`. Required by the schema.
  final String destinationLang;

  /// The translated `<body xml:lang='destination_lang'>` text.
  final String text;

  final String? sourceLang;
  final String? engine;
  final String? dictionary;
  final String? charset;

  /// `reviewed='true'`: machine translation a human has checked.
  final bool reviewed;
}

/// XEP-0171 payload read from an incoming message.
///
/// [sourceBody] is the original text (the body that is not a destination
/// language). Nothing here is written onto a stanza this client sends.
class LangTransData implements StanzaHandlerExtension {
  const LangTransData({
    required this.translations,
    this.sourceLang,
    this.sourceBody,
  });

  final List<LanguageTranslation> translations;

  /// Language of the original body, when known.
  final String? sourceLang;

  /// Original body text, when this was parsed from a stanza.
  final String? sourceBody;

  /// Reads `<x xmlns='urn:xmpp:langtrans'/>` and the matching bodies.
  ///
  /// Returns null when the element is absent or names no destination that
  /// has a body.
  static LangTransData? fromStanza(XMLNode stanza) {
    final x = stanza.firstTag('x', xmlns: langtransXmlns);
    if (x == null) return null;

    final hints = <_Hint>[];
    for (final child in x.children) {
      if (child.tag != 'translation') continue;
      final dest = _attr(child, 'destination_lang');
      if (dest == null) continue;
      hints.add(
        _Hint(
          destinationLang: dest,
          sourceLang: _attr(child, 'source_lang'),
          engine: _attr(child, 'engine'),
          dictionary: _attr(child, 'dictionary'),
          charset: _attr(child, 'charset'),
          reviewed: _flag(child.attributes['reviewed']),
        ),
      );
    }
    if (hints.isEmpty) return null;

    final bodies = stanza.findTags('body');
    final destinations = [for (final h in hints) h.destinationLang];
    final sourceBody = _sourceBody(bodies, hints, destinations);
    final items = <LanguageTranslation>[];
    for (final hint in hints) {
      final text = _bodyFor(bodies, hint.destinationLang);
      if (text == null || text.isEmpty) continue;
      items.add(
        LanguageTranslation(
          destinationLang: xmppLanguagePrimary(hint.destinationLang),
          text: text,
          sourceLang: hint.sourceLang == null
              ? null
              : xmppLanguagePrimary(hint.sourceLang!),
          engine: hint.engine,
          dictionary: hint.dictionary,
          charset: hint.charset,
          reviewed: hint.reviewed,
        ),
      );
    }
    if (items.isEmpty) return null;

    final sourceLang =
        _sharedSource(hints) ?? _sourceLangOf(bodies, destinations);
    return LangTransData(
      translations: items,
      sourceLang: sourceLang == null || sourceLang.isEmpty
          ? null
          : xmppLanguagePrimary(sourceLang),
      sourceBody: sourceBody,
    );
  }
}

/// One language pairing advertised by a translation provider.
class TranslationLanguagePair {
  const TranslationLanguagePair({
    required this.sourceLang,
    required this.destinationLang,
    this.engine,
    this.pivotable = false,
    this.dictionary,
    this.jid,
  });

  final String sourceLang;
  final String destinationLang;
  final String? engine;
  final bool pivotable;
  final String? dictionary;
  final String? jid;

  /// Reads `<item/>` children of a `urn:xmpp:langtrans:items` query.
  static List<TranslationLanguagePair> fromQuery(XMLNode query) {
    final items = <TranslationLanguagePair>[];
    for (final child in query.findTags('item')) {
      final source = _attr(child, 'source_lang');
      final destination = _attr(child, 'destination_lang');
      if (source == null || destination == null) continue;
      items.add(
        TranslationLanguagePair(
          sourceLang: xmppLanguagePrimary(source),
          destinationLang: xmppLanguagePrimary(destination),
          engine: _attr(child, 'engine'),
          pivotable: _flag(child.attributes['pivotable']),
          dictionary: _attr(child, 'dictionary'),
          jid: _attr(child, 'jid'),
        ),
      );
    }
    return items;
  }
}

/// One translation returned in an IQ result. The text is the element's body.
class RequestedTranslation {
  const RequestedTranslation({
    required this.destinationLang,
    required this.text,
    this.sourceLang,
    this.engine,
    this.dictionary,
  });

  final String destinationLang;
  final String text;
  final String? sourceLang;
  final String? engine;
  final String? dictionary;
}

/// IQ result for a translation request (XEP-0171 §4.3).
class TranslationResponse {
  const TranslationResponse({
    required this.translations,
    this.sourceLang,
    this.sourceText,
  });

  final List<RequestedTranslation> translations;
  final String? sourceLang;
  final String? sourceText;

  /// Reads `<x xmlns='urn:xmpp:langtrans'/>` on an IQ result.
  ///
  /// Returns null when the element is absent or no `<translation/>` has text.
  static TranslationResponse? fromStanza(XMLNode stanza) {
    final x = stanza.firstTag('x', xmlns: langtransXmlns);
    if (x == null) return null;
    final source = x.firstTag('source');
    final items = <RequestedTranslation>[];
    for (final child in x.findTags('translation')) {
      final dest = _attr(child, 'destination_lang');
      final text = child.innerText().trim();
      if (dest == null || text.isEmpty) continue;
      final sourceLang = _attr(child, 'source_lang');
      items.add(
        RequestedTranslation(
          destinationLang: xmppLanguagePrimary(dest),
          text: text,
          sourceLang: sourceLang == null
              ? null
              : xmppLanguagePrimary(sourceLang),
          engine: _attr(child, 'engine'),
          dictionary: _attr(child, 'dictionary'),
        ),
      );
    }
    if (items.isEmpty) return null;
    final sourceLang = source == null ? null : _attr(source, 'xml:lang');
    return TranslationResponse(
      translations: items,
      sourceLang: sourceLang == null ? null : xmppLanguagePrimary(sourceLang),
      sourceText: source?.innerText(),
    );
  }
}

/// `<x/>` for an IQ get that asks a provider to translate [text].
XMLNode translationRequestElement({
  required String text,
  String? sourceLang,
  required String destinationLang,
  String? dictionary,
}) {
  final source = xmppLanguagePrimary(sourceLang ?? '');
  final destination = xmppLanguagePrimary(destinationLang);
  final dict = dictionary?.trim() ?? '';
  return XMLNode.xmlns(
    tag: 'x',
    xmlns: langtransXmlns,
    children: [
      XMLNode(
        tag: 'source',
        text: text,
        attributes: {if (source.isNotEmpty) 'xml:lang': source},
      ),
      XMLNode(
        tag: 'translation',
        attributes: {
          'destination_lang': destination,
          if (dict.isNotEmpty) 'dictionary': dict,
        },
      ),
    ],
  );
}

class _Hint {
  const _Hint({
    required this.destinationLang,
    this.sourceLang,
    this.engine,
    this.dictionary,
    this.charset,
    this.reviewed = false,
  });

  final String destinationLang;
  final String? sourceLang;
  final String? engine;
  final String? dictionary;
  final String? charset;
  final bool reviewed;
}

String? _attr(XMLNode node, String name) {
  final raw = node.attributes[name];
  if (raw == null) return null;
  final text = raw.toString().trim();
  return text.isEmpty ? null : text;
}

bool _flag(Object? raw) {
  final text = raw?.toString().trim().toLowerCase();
  return text == 'true' || text == '1';
}

String? _bodyFor(List<XMLNode> bodies, String lang) {
  for (final body in bodies) {
    final tag = _attr(body, 'xml:lang');
    if (tag != null && xmppLanguageTagsMatch(tag, lang)) {
      return body.innerText();
    }
  }
  return null;
}

/// Body that is the original: matching `source_lang`, else a body whose
/// language is not a destination, else a body with no `xml:lang`.
String? _sourceBody(
  List<XMLNode> bodies,
  List<_Hint> hints,
  List<String> destinations,
) {
  final sources = {
    for (final hint in hints)
      if (hint.sourceLang != null) hint.sourceLang!,
  };
  for (final source in sources) {
    final text = _bodyFor(bodies, source);
    if (text != null) return text;
  }
  for (final body in bodies) {
    final tag = _attr(body, 'xml:lang');
    if (tag == null) return body.innerText();
    final isDestination = destinations.any(
      (dest) => xmppLanguageTagsMatch(dest, tag),
    );
    if (!isDestination) return body.innerText();
  }
  return bodies.isEmpty ? null : bodies.first.innerText();
}

String? _sharedSource(List<_Hint> hints) {
  String? source;
  for (final hint in hints) {
    final lang = hint.sourceLang;
    if (lang == null) continue;
    if (source == null) {
      source = lang;
      continue;
    }
    if (!xmppLanguageTagsMatch(source, lang)) return source;
  }
  return source;
}

String? _sourceLangOf(List<XMLNode> bodies, List<String> destinations) {
  for (final body in bodies) {
    final tag = _attr(body, 'xml:lang');
    if (tag == null) continue;
    final isDestination = destinations.any(
      (dest) => xmppLanguageTagsMatch(dest, tag),
    );
    if (!isDestination) return tag;
  }
  return null;
}

/// Asks remote translation providers for a translation. Does not advertise
/// this client as a provider, and does not answer translation requests.
class LanguageTranslationManager extends XmppManagerBase {
  LanguageTranslationManager() : super(languageTranslationManager);

  @override
  List<StanzaHandler> getIncomingStanzaHandlers() => [
    StanzaHandler(
      stanzaTag: 'message',
      tagName: 'x',
      tagXmlns: langtransXmlns,
      callback: _onMessage,
      priority: messageExtensionPriority,
    ),
  ];

  @override
  Future<bool> isSupported() async => true;

  Future<StanzaHandlerData> _onMessage(
    Stanza stanza,
    StanzaHandlerData state,
  ) async {
    final parsed = LangTransData.fromStanza(stanza);
    if (parsed == null) return state;
    state.extensions.set(parsed);
    final source = parsed.sourceBody;
    if (source != null) {
      state.extensions.set(MessageBodyData(source, xmlLang: parsed.sourceLang));
    }
    return state;
  }

  /// `urn:xmpp:langtrans:items` on [entity].
  Future<Result<StanzaError, List<TranslationLanguagePair>>> queryItems(
    JID entity,
  ) async {
    final stanza = await getAttributes().sendStanza(
      StanzaDetails(
        Stanza.iq(
          to: entity.toString(),
          type: 'get',
          children: [XMLNode.xmlns(tag: 'query', xmlns: langtransItemsXmlns)],
        ),
        shouldEncrypt: false,
      ),
    );
    return _pairsFrom(stanza);
  }

  /// IQ get asking [provider] to translate [text] into [destinationLang].
  Future<Result<StanzaError, TranslationResponse>> requestTranslation(
    JID provider, {
    required String text,
    String? sourceLang,
    required String destinationLang,
    String? dictionary,
  }) async {
    final stanza = await getAttributes().sendStanza(
      StanzaDetails(
        Stanza.iq(
          to: provider.toString(),
          type: 'get',
          children: [
            translationRequestElement(
              text: text,
              sourceLang: sourceLang,
              destinationLang: destinationLang,
              dictionary: dictionary,
            ),
          ],
        ),
        shouldEncrypt: false,
      ),
    );
    if (stanza == null) {
      return Result(UnknownStanzaError());
    }
    if (stanza.attributes['type'] == 'error') {
      return Result(StanzaError.fromXMLNode(stanza) ?? UnknownStanzaError());
    }
    final parsed = TranslationResponse.fromStanza(stanza);
    if (parsed == null) return Result(UnknownStanzaError());
    return Result(parsed);
  }
}

Result<StanzaError, List<TranslationLanguagePair>> _pairsFrom(XMLNode? stanza) {
  if (stanza == null) return Result(UnknownStanzaError());
  if (stanza.attributes['type'] == 'error') {
    return Result(StanzaError.fromXMLNode(stanza) ?? UnknownStanzaError());
  }
  final query = stanza.firstTag('query', xmlns: langtransItemsXmlns);
  if (query == null) return Result(UnknownStanzaError());
  return Result(TranslationLanguagePair.fromQuery(query));
}
