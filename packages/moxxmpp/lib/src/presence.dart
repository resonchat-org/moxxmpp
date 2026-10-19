import 'dart:async';

import 'package:moxlib/moxlib.dart';
import 'package:moxxmpp/src/events.dart';
import 'package:moxxmpp/src/jid.dart';
import 'package:moxxmpp/src/managers/base.dart';
import 'package:moxxmpp/src/managers/data.dart';
import 'package:moxxmpp/src/managers/handlers.dart';
import 'package:moxxmpp/src/managers/namespaces.dart';
import 'package:moxxmpp/src/managers/priorities.dart';
import 'package:moxxmpp/src/namespaces.dart';
import 'package:moxxmpp/src/negotiators/namespaces.dart';
import 'package:moxxmpp/src/negotiators/negotiator.dart';
import 'package:moxxmpp/src/stanza.dart';
import 'package:moxxmpp/src/stringxml.dart';
import 'package:moxxmpp/src/util/typed_map.dart';
import 'package:moxxmpp/src/xeps/xep_0198/types.dart';

/// A function that will be called when presence, outside of subscription request
/// management, will be sent. Useful for managers that want to add [XMLNode]s to said
/// presence.
typedef PresencePreSendCallback = Future<List<XMLNode>> Function();

/// Availability sub-state from RFC 6121 §4.7.2.1 `<show/>`.
///
/// Absence of `<show/>` means the entity is online and available ([online]).
enum PresenceShow {
  /// No `<show/>` — online and available.
  online,

  /// Actively interested in chatting.
  chat,

  /// Temporarily away.
  away,

  /// Away for an extended period (eXtended Away).
  xa,

  /// Busy (Do Not Disturb).
  dnd;

  /// Wire text for `<show/>`, or `null` when the element must be omitted.
  String? get wire => switch (this) {
    PresenceShow.online => null,
    PresenceShow.chat => 'chat',
    PresenceShow.away => 'away',
    PresenceShow.xa => 'xa',
    PresenceShow.dnd => 'dnd',
  };

  /// Higher means more available — used to pick the best resource.
  ///
  /// Matches the usual client ordering (chat > online > away > xa > dnd).
  int get rank => switch (this) {
    PresenceShow.chat => 4,
    PresenceShow.online => 3,
    PresenceShow.away => 2,
    PresenceShow.xa => 1,
    PresenceShow.dnd => 0,
  };

  /// Parses RFC 6121 `<show/>` text. Unknown values become [online].
  static PresenceShow parse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case null:
      case '':
        return PresenceShow.online;
      case 'chat':
        return PresenceShow.chat;
      case 'away':
        return PresenceShow.away;
      case 'xa':
        return PresenceShow.xa;
      case 'dnd':
        return PresenceShow.dnd;
      default:
        return PresenceShow.online;
    }
  }
}

/// Parsed presence payload (RFC 6121 §4.7), excluding subscription management.
class PresenceData {
  const PresenceData({
    required this.from,
    required this.available,
    this.show = PresenceShow.online,
    this.status,
    this.priority = 0,
  });

  /// Full JID of the sender when present.
  final JID from;

  /// `true` for available presence (no `type`); `false` for `unavailable`.
  final bool available;

  /// `<show/>` sub-state; ignored when [available] is false.
  final PresenceShow show;

  /// Optional human-readable `<status/>` (first language variant).
  final String? status;

  /// `<priority/>` (−128…127); defaults to 0 when absent.
  final int priority;
}

/// Fired for available / unavailable presence (RFC 6121 §4.2 / §4.5).
///
/// Subscription management uses [SubscriptionRequestReceivedEvent] instead.
/// [extensions] holds data other managers attached (for example XEP-0319).
class PresenceReceivedEvent extends XmppEvent {
  PresenceReceivedEvent(this.data, this.extensions);
  final PresenceData data;
  final TypedMap<StanzaHandlerExtension> extensions;

  T? get<T>() => extensions.get<T>();
}

/// A pseudo-negotiator that does not really negotiate anything. Instead, its purpose
/// is to look for a stream feature indicating that we can pre-approve subscription
/// requests, shown by [PresenceNegotiator.preApprovalSupported].
class PresenceNegotiator extends XmppFeatureNegotiatorBase {
  PresenceNegotiator()
    : super(11, false, subscriptionPreApprovalXmlns, presenceNegotiator);

  /// Flag indicating whether presence subscription pre-approval is supported
  bool _supported = false;
  bool get preApprovalSupported => _supported;

  @override
  Future<Result<NegotiatorState, NegotiatorError>> negotiate(
    XMLNode nonza,
  ) async {
    _supported = true;
    return const Result(NegotiatorState.done);
  }

  @override
  void reset() {
    _supported = false;

    super.reset();
  }
}

/// A mandatory manager that handles initial presence sending, sending of subscription
/// request management requests and triggers events for incoming presence stanzas.
///
/// Presence syntax follows RFC 6121 §4 (not a XEP).
class PresenceManager extends XmppManagerBase {
  PresenceManager() : super(presenceManager);

  /// The list of pre-send callbacks.
  final List<PresencePreSendCallback> _presenceCallbacks = List.empty(
    growable: true,
  );

  /// Last broadcast availability sub-state (used by [sendInitialPresence]).
  PresenceShow _show = PresenceShow.chat;

  /// Optional status text included in available presence.
  String? _status;

  /// Optional resource priority (−128…127).
  int? _priority;

  /// Current availability sub-state we advertise.
  PresenceShow get show => _show;

  /// Current status text we advertise, if any.
  String? get status => _status;

  @override
  List<StanzaHandler> getIncomingStanzaHandlers() => [
    StanzaHandler(
      stanzaTag: 'presence',
      callback: _onPresence,
      // Extensions must use [presenceExtensionPriority] (or higher) so they
      // run before this handler terminates the pipeline.
      priority: presenceHandlerPriority,
    ),
  ];

  @override
  List<String> getDiscoFeatures() => [capsXmlns];

  @override
  Future<bool> isSupported() async => true;

  /// Register the pre-send callback [callback].
  void registerPreSendCallback(PresencePreSendCallback callback) {
    _presenceCallbacks.add(callback);
  }

  /// Sets defaults used by the next [sendPresence] / [sendInitialPresence].
  ///
  /// Does not send a stanza; call [sendPresence] when already connected.
  void configure({
    PresenceShow? show,
    String? status,
    int? priority,
    bool clearStatus = false,
  }) {
    if (show != null) _show = show;
    if (clearStatus) {
      _status = null;
    } else if (status != null) {
      _status = status;
    }
    if (priority != null) _priority = priority;
  }

  @override
  Future<void> onXmppEvent(XmppEvent event) async {
    if (event is StreamNegotiationsDoneEvent) {
      // Send initial presence only when we have not resumed the stream
      if (!event.resumed) {
        await sendInitialPresence();
      }
    }
  }

  Future<StanzaHandlerData> _onPresence(
    Stanza presence,
    StanzaHandlerData state,
  ) async {
    final attrs = getAttributes();
    final type = presence.type;

    switch (type) {
      case 'subscribe':
      case 'subscribed':
        {
          if (presence.from == null) return state..done = true;
          attrs.sendEvent(
            SubscriptionRequestReceivedEvent(
              from: JID.fromString(presence.from!),
            ),
          );
          return state..done = true;
        }
      case 'unsubscribe':
      case 'unsubscribed':
      case 'probe':
      case 'error':
        // Subscription teardown / probes / errors are not availability updates.
        return state..done = true;
      default:
        break;
    }

    final fromRaw = presence.from;
    if (fromRaw == null) {
      return state;
    }

    final from = JID.fromString(fromRaw);
    final available = type == null || type.isEmpty;
    final unavailable = type == 'unavailable';

    if (!available && !unavailable) {
      // Unknown type — ignore rather than inventing semantics.
      return state..done = true;
    }

    final showRaw = presence.firstTag('show')?.innerText();
    final statusRaw = presence.firstTag('status')?.innerText();
    final priorityRaw = presence.firstTag('priority')?.innerText();
    var priority = 0;
    if (priorityRaw != null && priorityRaw.isNotEmpty) {
      priority = int.tryParse(priorityRaw.trim()) ?? 0;
      if (priority < -128) priority = -128;
      if (priority > 127) priority = 127;
    }

    final data = PresenceData(
      from: from,
      available: available,
      show: available ? PresenceShow.parse(showRaw) : PresenceShow.online,
      status: (statusRaw == null || statusRaw.isEmpty) ? null : statusRaw,
      priority: priority,
    );

    logger.finest(
      "Received ${available ? 'available' : 'unavailable'} presence "
      "from '$fromRaw' show=${data.show.name}",
    );

    attrs.sendEvent(PresenceReceivedEvent(data, state.extensions));
    return state..done = true;
  }

  /// Sends the initial presence to enable receiving messages.
  Future<void> sendInitialPresence() => sendPresence();

  /// Broadcasts available presence with the configured [show] / status / priority.
  ///
  /// Per RFC 6121 §4.7.2.1, [PresenceShow.online] omits `<show/>`.
  Future<void> sendPresence({
    PresenceShow? show,
    String? status,
    int? priority,
    bool clearStatus = false,
  }) async {
    configure(
      show: show,
      status: status,
      priority: priority,
      clearStatus: clearStatus,
    );

    final children = <XMLNode>[];
    final showWire = _show.wire;
    if (showWire != null) {
      children.add(XMLNode(tag: 'show', text: showWire));
    }
    if (_status != null && _status!.isNotEmpty) {
      children.add(XMLNode(tag: 'status', text: _status));
    }
    if (_priority != null) {
      children.add(XMLNode(tag: 'priority', text: '${_priority!}'));
    }

    for (final callback in _presenceCallbacks) {
      children.addAll(await callback());
    }

    final attrs = getAttributes();
    await attrs.sendStanza(
      StanzaDetails(
        Stanza.presence(children: children),
        awaitable: false,
        addId: false,
      ),
    );
  }

  /// Send an unavailable presence with no 'to' attribute.
  Future<void> sendUnavailablePresence() async {
    // Bypass the queue so that this get's sent immediately.
    // If we do it like this, we can also block the disconnection
    // until we're actually ready.
    await getAttributes().sendStanza(
      StanzaDetails(
        Stanza.presence(type: 'unavailable'),
        awaitable: false,
        bypassQueue: true,
        postSendExtensions: TypedMap<StanzaHandlerExtension>.fromList([
          const StreamManagementData(true, null),
        ]),
      ),
    );
  }

  /// Similar to [requestSubscription], but it also tells the server to automatically
  /// accept a subscription request from [to], should it arrive.
  /// This requires a [PresenceNegotiator] to be registered as this feature is optional.
  ///
  /// Returns true, when the stanza was sent. Returns false, when the stanza was not sent,
  /// for example because the server does not support subscription pre-approvals.
  Future<bool> preApproveSubscription(JID to) async {
    final negotiator = getAttributes().getNegotiatorById<PresenceNegotiator>(
      presenceNegotiator,
    );
    assert(negotiator != null, 'No PresenceNegotiator registered');

    if (!negotiator!.preApprovalSupported) {
      return false;
    }

    await getAttributes().sendStanza(
      StanzaDetails(
        Stanza.presence(type: 'subscribed', to: to.toString()),
        awaitable: false,
      ),
    );
    return true;
  }

  /// Sends a subscription request to [to].
  Future<void> requestSubscription(JID to) async {
    await getAttributes().sendStanza(
      StanzaDetails(
        Stanza.presence(type: 'subscribe', to: to.toString()),
        awaitable: false,
      ),
    );
  }

  /// Accept a subscription request from [to].
  Future<void> acceptSubscriptionRequest(JID to) async {
    await getAttributes().sendStanza(
      StanzaDetails(
        Stanza.presence(type: 'subscribed', to: to.toString()),
        awaitable: false,
      ),
    );
  }

  /// Send a subscription request rejection to [to].
  Future<void> rejectSubscriptionRequest(JID to) async {
    await getAttributes().sendStanza(
      StanzaDetails(
        Stanza.presence(type: 'unsubscribed', to: to.toString()),
        awaitable: false,
      ),
    );
  }

  /// Sends an unsubscription request to [to].
  Future<void> unsubscribe(JID to) async {
    await getAttributes().sendStanza(
      StanzaDetails(
        Stanza.presence(type: 'unsubscribe', to: to.toString()),
        awaitable: false,
      ),
    );
  }
}
