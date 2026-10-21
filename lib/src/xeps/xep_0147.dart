// XEP-0147: XMPP URI Scheme (https://xmpp.org/extensions/xep-0147.html)
//
// Parsing follows RFC 5122 / XEP-0147 query form and matches Gajim's
// `parse_xmpp_uri_query` / `XmppIri` (authority component not supported).

import 'package:meta/meta.dart';

import 'package:moxxmpp/src/jid.dart';

/// Known querytypes handled by common clients (Gajim `XmppUriQuery` +
/// registered `join` from the XMPP URI querytype registry).
enum XmppUriQuerytype {
  /// No query component (`xmpp:jid` with no `?`).
  none,

  /// XEP-0147 §3.1 — open a message composer / chat.
  message,

  /// XEP-0147 §3.2.1 — add/edit roster item.
  roster,

  /// Registered querytype for joining a MUC (XEP-0045 / registry).
  join,
}

/// Parsed `xmpp:` IRI/URI (XEP-0147).
@immutable
class XmppUri {
  const XmppUri({
    required this.jid,
    required this.querytype,
    required this.params,
    required this.hasQuery,
    required this.raw,
  });

  /// Entity addressed by the path (authority form is rejected).
  final JID jid;

  /// First query segment before `;` (empty when [hasQuery] is false).
  final String querytype;

  /// Key/value pairs after the querytype (`body`, `subject`, `password`, …).
  final Map<String, String> params;

  /// True when the URI contained a `?` (even if the query is empty).
  final bool hasQuery;

  final String raw;

  /// Mapped known querytype, or null when [hasQuery] and the type is unknown.
  XmppUriQuerytype? get knownQuerytype {
    if (!hasQuery) return XmppUriQuerytype.none;
    switch (querytype) {
      case 'message':
        return XmppUriQuerytype.message;
      case 'roster':
        return XmppUriQuerytype.roster;
      case 'join':
        return XmppUriQuerytype.join;
      case '':
        // `xmpp:jid?` with empty querytype — treat like none for handlers.
        return XmppUriQuerytype.none;
      default:
        return null;
    }
  }

  String? get body => params['body'];
  String? get subject => params['subject'];
  String? get password => params['password'];
  String? get name => params['name'];

  /// Parse [input] as an `xmpp:` URI. Returns null when invalid.
  ///
  /// Authority form (`xmpp://…`) is rejected (same as Gajim).
  static XmppUri? tryParse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.toLowerCase().startsWith('xmpp:')) return null;

    final rest = trimmed.substring(5);
    // Reject authority component: xmpp://host/…
    if (rest.startsWith('//')) return null;
    if (rest.isEmpty) return null;

    final qIndex = rest.indexOf('?');
    final hasQuery = qIndex >= 0;
    final pathPct = hasQuery ? rest.substring(0, qIndex) : rest;
    final queryPct = hasQuery ? rest.substring(qIndex + 1) : '';

    if (pathPct.isEmpty) return null;

    late final String jidString;
    try {
      jidString = Uri.decodeComponent(pathPct);
    } catch (_) {
      return null;
    }

    late final JID jid;
    try {
      jid = JID.fromString(jidString);
    } catch (_) {
      return null;
    }
    if (jid.domain.isEmpty) return null;

    final parsedQuery = _parseQuery(queryPct);
    return XmppUri(
      jid: jid.toBare(),
      querytype: parsedQuery.querytype,
      params: parsedQuery.params,
      hasQuery: hasQuery,
      raw: trimmed,
    );
  }

  /// XEP-0147 / RFC 5122: `iquerytype (;ikey=ival)*` with `;` separators.
  static ({String querytype, Map<String, String> params}) _parseQuery(
    String pctIquerycomp,
  ) {
    if (pctIquerycomp.isEmpty) {
      return (querytype: '', params: const {});
    }

    final semi = pctIquerycomp.indexOf(';');
    final pctQuerytype = semi < 0
        ? pctIquerycomp
        : pctIquerycomp.substring(0, semi);
    final pctIpairs = semi < 0 ? '' : pctIquerycomp.substring(semi + 1);

    String querytype;
    try {
      querytype = Uri.decodeComponent(pctQuerytype);
    } catch (_) {
      querytype = pctQuerytype;
    }

    if (pctIpairs.isEmpty) {
      return (querytype: querytype, params: const {});
    }

    final pairs = <String, String>{};
    for (final pctIpair in pctIpairs.split(';')) {
      if (pctIpair.isEmpty) continue;
      final eq = pctIpair.indexOf('=');
      final pctIkey = eq < 0 ? pctIpair : pctIpair.substring(0, eq);
      final pctIval = eq < 0 ? '' : pctIpair.substring(eq + 1);
      String key;
      String value;
      try {
        key = Uri.decodeComponent(pctIkey);
      } catch (_) {
        key = pctIkey;
      }
      try {
        value = Uri.decodeComponent(pctIval);
      } catch (_) {
        value = pctIval;
      }
      pairs[key] = value;
    }
    return (querytype: querytype, params: pairs);
  }
}
