import 'package:moxlib/moxlib.dart';

import 'package:moxxmpp/src/events.dart';
import 'package:moxxmpp/src/jid.dart';
import 'package:moxxmpp/src/managers/base.dart';
import 'package:moxxmpp/src/managers/namespaces.dart';
import 'package:moxxmpp/src/namespaces.dart';
import 'package:moxxmpp/src/stringxml.dart';
import 'package:moxxmpp/src/xeps/xep_0030/xep_0030.dart';
import 'package:moxxmpp/src/xeps/xep_0060/errors.dart';
import 'package:moxxmpp/src/xeps/xep_0060/xep_0060.dart';

/// One conference bookmark (XEP-0402 / legacy XEP-0048 conference).
class ConferenceBookmark {
  const ConferenceBookmark({
    required this.jid,
    this.name,
    this.nick,
    this.password,
    this.autoJoin = false,
    this.extensions = const [],
  });

  /// Bare room JID (also the XEP-0402 PubSub item id).
  final String jid;

  final String? name;
  final String? nick;
  final String? password;
  final bool autoJoin;

  /// Foreign children inside `<extensions/>`, preserved across rewrites.
  final List<XMLNode> extensions;

  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final at = jid.indexOf('@');
    return at < 0 ? jid : jid.substring(0, at);
  }

  ConferenceBookmark copyWith({
    String? name,
    String? nick,
    String? password,
    bool? autoJoin,
    List<XMLNode>? extensions,
  }) {
    return ConferenceBookmark(
      jid: jid,
      name: name ?? this.name,
      nick: nick ?? this.nick,
      password: password ?? this.password,
      autoJoin: autoJoin ?? this.autoJoin,
      extensions: extensions ?? this.extensions,
    );
  }

  /// XEP-0402 `<conference xmlns='urn:xmpp:bookmarks:1'/>` payload.
  XMLNode toNativeXml() {
    return XMLNode.xmlns(
      tag: 'conference',
      xmlns: bookmarks2Xmlns,
      attributes: {
        if (autoJoin) 'autojoin': 'true',
        if (name != null && name!.isNotEmpty) 'name': name!,
      },
      children: [
        if (nick != null && nick!.isNotEmpty) XMLNode(tag: 'nick', text: nick),
        if (password != null && password!.isNotEmpty)
          XMLNode(tag: 'password', text: password),
        if (extensions.isNotEmpty)
          XMLNode(tag: 'extensions', children: extensions),
      ],
    );
  }

  /// Legacy XEP-0048 `<conference/>` child of `<storage/>`.
  XMLNode toLegacyXml() {
    return XMLNode(
      tag: 'conference',
      attributes: {
        'jid': jid,
        if (autoJoin) 'autojoin': 'true',
        if (name != null && name!.isNotEmpty) 'name': name,
      },
      children: [
        if (nick != null && nick!.isNotEmpty) XMLNode(tag: 'nick', text: nick),
        if (password != null && password!.isNotEmpty)
          XMLNode(tag: 'password', text: password),
      ],
    );
  }

  static ConferenceBookmark? fromNativeItem(String id, XMLNode payload) {
    if (payload.tag != 'conference') return null;
    final jid = JID.fromString(id).toBare().toString();
    if (jid.contains('/')) return null;
    return ConferenceBookmark(
      jid: jid,
      name: _attr(payload, 'name'),
      autoJoin: _truthy(payload.attributes['autojoin']),
      nick: payload.firstTag('nick')?.text,
      password: payload.firstTag('password')?.text,
      extensions: payload.firstTag('extensions')?.children ?? const [],
    );
  }

  static ConferenceBookmark? fromLegacyConference(XMLNode conference) {
    if (conference.tag != 'conference') return null;
    final raw = conference.attributes['jid'] as String?;
    if (raw == null || raw.isEmpty) return null;
    final jid = JID.fromString(raw).toBare().toString();
    return ConferenceBookmark(
      jid: jid,
      name: _attr(conference, 'name'),
      autoJoin: _truthy(conference.attributes['autojoin']),
      nick: conference.firstTag('nick')?.text,
      password: conference.firstTag('password')?.text,
    );
  }

  static String? _attr(XMLNode node, String key) {
    final v = node.attributes[key] as String?;
    if (v == null || v.trim().isEmpty) return null;
    return v;
  }

  static bool _truthy(Object? value) {
    if (value is! String) return false;
    final v = value.toLowerCase();
    return v == 'true' || v == '1';
  }
}

/// Fired when the local bookmark cache changes (fetch, push, publish, retract).
class BookmarksUpdatedEvent extends XmppEvent {
  BookmarksUpdatedEvent(this.bookmarks);
  final List<ConferenceBookmark> bookmarks;
}

/// Which wire format [BookmarksManager] is currently using.
enum BookmarksTransport {
  /// XEP-0402: one PubSub item per bare JID on `urn:xmpp:bookmarks:1`.
  native,

  /// XEP-0048 via PEP conversion: single `storage:bookmarks` item `current`.
  legacy,
}

/// XEP-0402 PEP Native Bookmarks, with XEP-0048 PEP-conversion fallback.
///
/// Conversations' BookmarkManager / NativeBookmarkManager / LegacyBookmarkManager
/// preference order: native when `#compat` is advertised, else legacy conversion
/// (wait for / fetch the singleton), else nothing.
///
/// Requires a [PubSubManager] registered on the same connection.
class BookmarksManager extends XmppManagerBase {
  BookmarksManager() : super(bookmarksManager);

  final Map<String, ConferenceBookmark> _bookmarks = {};
  BookmarksTransport? _transport;
  bool _gotFeatures = false;
  bool _native = false;
  bool _legacy = false;

  /// Cached bookmarks keyed by bare JID (lowercase).
  List<ConferenceBookmark> get bookmarks =>
      List<ConferenceBookmark>.unmodifiable(_bookmarks.values);

  BookmarksTransport? get transport => _transport;

  PubSubManager get _pubsub =>
      getAttributes().getManagerById<PubSubManager>(pubsubManager)!;

  JID get _ownBare => getAttributes().getFullJID().toBare();

  @override
  List<String> getDiscoFeatures() => [
    '$bookmarks2Xmlns+notify',
    '$bookmarksXmlns+notify',
  ];

  @override
  Future<bool> isSupported() async {
    await _ensureFeatures();
    return _native || _legacy;
  }

  @override
  Future<void> onXmppEvent(XmppEvent event) async {
    if (event is StreamNegotiationsDoneEvent) {
      if (!event.resumed) {
        _gotFeatures = false;
        _native = false;
        _legacy = false;
        _transport = null;
      }
      return;
    }

    if (event is PubSubNotificationEvent) {
      await _onNotification(event);
      return;
    }
    if (event is PubSubRetractEvent) {
      await _onRetract(event);
      return;
    }
    if (event is PubSubNodeDeletedEvent || event is PubSubNodePurgedEvent) {
      final node = event is PubSubNodeDeletedEvent
          ? event.node
          : (event as PubSubNodePurgedEvent).node;
      if (node == bookmarks2Xmlns || node == bookmarksXmlns) {
        _bookmarks.clear();
        _emit();
      }
    }
  }

  Future<void> _ensureFeatures() async {
    if (_gotFeatures) return;
    final disco = getAttributes().getManagerById<DiscoManager>(discoManager)!;
    final bare = _ownBare;
    _native = await disco.supportsFeature(bare, bookmarks2CompatXmlns);
    _legacy = await disco.supportsFeature(bare, bookmarksConversionXmlns);
    _gotFeatures = true;
    if (_native) {
      _transport = BookmarksTransport.native;
    } else if (_legacy) {
      _transport = BookmarksTransport.legacy;
    }
  }

  /// Seeds the in-memory cache from local storage without emitting an event.
  ///
  /// Used on cold start so UI / legacy rewrite see last-known bookmarks
  /// before the PEP fetch completes.
  void seedCache(Iterable<ConferenceBookmark> bookmarks) {
    _bookmarks
      ..clear()
      ..addAll({for (final b in bookmarks) b.jid.toLowerCase(): b});
  }

  /// Fetches bookmarks from PEP and replaces the local cache.
  Future<Result<PubSubError, List<ConferenceBookmark>>> fetch() async {
    await _ensureFeatures();
    if (_native) {
      final result = await _fetchNative();
      if (result.isType<PubSubError>()) {
        return Result(result.get<PubSubError>());
      }
      _replaceAll(result.get<List<ConferenceBookmark>>());
      return Result(bookmarks);
    }
    if (_legacy) {
      final result = await _fetchLegacy();
      if (result.isType<PubSubError>()) {
        return Result(result.get<PubSubError>());
      }
      _replaceAll(result.get<List<ConferenceBookmark>>());
      return Result(bookmarks);
    }
    return const Result(<ConferenceBookmark>[]);
  }

  /// Publishes or updates one conference bookmark.
  Future<Result<PubSubError, bool>> publish(ConferenceBookmark bookmark) async {
    await _ensureFeatures();
    final bare = JID.fromString(bookmark.jid).toBare().toString();
    final normalised = ConferenceBookmark(
      jid: bare,
      name: bookmark.name,
      nick: bookmark.nick,
      password: bookmark.password,
      autoJoin: bookmark.autoJoin,
      extensions: bookmark.extensions,
    );

    if (_native) {
      final ok = await _pubsub.publish(
        _ownBare,
        bookmarks2Xmlns,
        normalised.toNativeXml(),
        id: bare,
        options: const PubSubPublishOptions(
          accessModel: 'whitelist',
          maxItems: 'max',
        ),
      );
      if (ok.isType<PubSubError>()) return Result(ok.get<PubSubError>());
      _bookmarks[bare.toLowerCase()] = normalised;
      _emit();
      return const Result(true);
    }

    if (_legacy) {
      _bookmarks[bare.toLowerCase()] = normalised;
      final ok = await _publishLegacyAll();
      if (ok.isType<PubSubError>()) return Result(ok.get<PubSubError>());
      _emit();
      return const Result(true);
    }

    return Result(UnknownPubSubError());
  }

  /// Removes one bookmark by bare room JID.
  Future<Result<PubSubError, bool>> retract(String roomJid) async {
    await _ensureFeatures();
    final bare = JID.fromString(roomJid).toBare().toString();
    if (_native) {
      final ok = await _pubsub.retract(_ownBare, bookmarks2Xmlns, bare);
      if (ok.isType<PubSubError>()) return Result(ok.get<PubSubError>());
      _bookmarks.remove(bare.toLowerCase());
      _emit();
      return const Result(true);
    }
    if (_legacy) {
      _bookmarks.remove(bare.toLowerCase());
      final ok = await _publishLegacyAll();
      if (ok.isType<PubSubError>()) return Result(ok.get<PubSubError>());
      _emit();
      return const Result(true);
    }
    return Result(UnknownPubSubError());
  }

  Future<Result<PubSubError, List<ConferenceBookmark>>> _fetchNative() async {
    final result = await _pubsub.getItems(_ownBare, bookmarks2Xmlns);
    if (result.isType<PubSubError>()) return Result(result.get<PubSubError>());
    final list = <ConferenceBookmark>[];
    for (final item in result.get<List<PubSubItem>>()) {
      final b = ConferenceBookmark.fromNativeItem(item.id, item.payload);
      if (b != null) list.add(b);
    }
    return Result(list);
  }

  Future<Result<PubSubError, List<ConferenceBookmark>>> _fetchLegacy() async {
    final result = await _pubsub.getItem(_ownBare, bookmarksXmlns, 'current');
    if (result.isType<PubSubError>()) {
      // Empty node is common on first use.
      return const Result(<ConferenceBookmark>[]);
    }
    final payload = result.get<PubSubItem>().payload;
    if (payload.tag != 'storage') {
      return const Result(<ConferenceBookmark>[]);
    }
    final list = <ConferenceBookmark>[];
    for (final conf in payload.findTags('conference')) {
      final b = ConferenceBookmark.fromLegacyConference(conf);
      if (b != null) list.add(b);
    }
    return Result(list);
  }

  Future<Result<PubSubError, bool>> _publishLegacyAll() {
    final storage = XMLNode.xmlns(
      tag: 'storage',
      xmlns: bookmarksXmlns,
      children: [for (final b in _bookmarks.values) b.toLegacyXml()],
    );
    return _pubsub.publish(
      _ownBare,
      bookmarksXmlns,
      storage,
      id: 'current',
      options: const PubSubPublishOptions(
        accessModel: 'whitelist',
        maxItems: 'max',
      ),
    );
  }

  Future<void> _onNotification(PubSubNotificationEvent event) async {
    if (event.item.node == bookmarks2Xmlns) {
      final b = ConferenceBookmark.fromNativeItem(
        event.item.id,
        event.item.payload,
      );
      if (b == null) return;
      _transport ??= BookmarksTransport.native;
      _bookmarks[b.jid.toLowerCase()] = b;
      _emit();
      return;
    }
    if (event.item.node == bookmarksXmlns) {
      final payload = event.item.payload;
      if (payload.tag != 'storage') return;
      _transport ??= BookmarksTransport.legacy;
      final next = <String, ConferenceBookmark>{};
      for (final conf in payload.findTags('conference')) {
        final b = ConferenceBookmark.fromLegacyConference(conf);
        if (b != null) next[b.jid.toLowerCase()] = b;
      }
      _bookmarks
        ..clear()
        ..addAll(next);
      _emit();
    }
  }

  Future<void> _onRetract(PubSubRetractEvent event) async {
    if (event.node != bookmarks2Xmlns) return;
    final key = JID.fromString(event.id).toBare().toString().toLowerCase();
    if (_bookmarks.remove(key) != null) _emit();
  }

  void _replaceAll(List<ConferenceBookmark> list) {
    _bookmarks
      ..clear()
      ..addAll({for (final b in list) b.jid.toLowerCase(): b});
    _emit();
  }

  void _emit() {
    getAttributes().sendEvent(BookmarksUpdatedEvent(bookmarks));
  }
}
