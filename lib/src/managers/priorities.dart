// Incoming stanza handlers run highest-first (see XmppConnection).
//
// Documented ladder — apps that register pre-handlers (PQ decrypt, blocklist
// drop, …) should pick a named constant from this file rather than inventing
// another magic number:
//
//   stream management (SM ack) ............... streamManagementPriority (9999)
//   MAM / carbons unwrap ..................... stanzaUnwrapPriority (300)
//   blocklist drop (app) ..................... blockedInboundPriority (300)
//   delayed delivery / PQ decrypt ............ delayedDeliveryPriority /
//                                              pqDecryptPriority (200)
//   OMEMO outgoing encrypt ................... omemoOutgoingEncryptPriority (100)
//   OMEMO incoming decrypt (default) ......... omemoIncomingDecryptPriority (0)
//   StanzaHandler default .................... stanzaHandlerDefaultPriority (0)
//   late message extensions (SFS) ............ messageExtensionLatePriority (-98)
//   typical message / presence extensions .... messageExtensionPriority /
//                                              presenceExtensionPriority (-99)
//   MessageManager / PresenceManager ......... messageHandlerPriority /
//                                              presenceHandlerPriority (-100)
//
// Monocles' MessageParser unwraps MAM (`<result/>`) and carbons
// (`<received/>`/`<sent/>`) *before* looking for `<encrypted/>` and
// decrypting — so archive/carbon copies take the same decrypt path as live
// stanzas. [stanzaUnwrapPriority] must stay above OMEMO incoming and PQ.

/// XEP-0198 stream management: outermost inbound stanza processing.
const int streamManagementPriority = 9999;

/// Unwrap XEP-0313 MAM `<result/>` / XEP-0280 carbons before decryption.
const int stanzaUnwrapPriority = 300;

/// Drop messages from blocked JIDs before any decrypt (app-side pre-handler).
///
/// Same numeric band as [stanzaUnwrapPriority]; registration order decides ties.
const int blockedInboundPriority = 300;

/// XEP-0203 delayed delivery: parse `<delay/>` early on inbound messages.
const int delayedDeliveryPriority = 200;

/// Post-quantum OMEMO2 decrypt (app pre-handler). Below unwrap, above classic
/// OMEMO incoming (default 0); namespaces keep the two decryptors from colliding.
const int pqDecryptPriority = 200;

/// XEP-0384 classic OMEMO: encrypt on the outgoing pre-handler path.
const int omemoOutgoingEncryptPriority = 100;

/// XEP-0384 classic OMEMO: inbound decrypt (explicit default priority).
const int omemoIncomingDecryptPriority = 0;

/// [StanzaHandler] constructor default when [priority] is omitted.
const int stanzaHandlerDefaultPriority = 0;

/// Message extensions that must run *after* the common −99 parsers (e.g. SFS).
const int messageExtensionLatePriority = -98;

/// Typical inbound message extension parsers (receipts, chat states, …).
///
/// Must be greater than [messageHandlerPriority] so they run before
/// [MessageManager] terminates processing.
const int messageExtensionPriority = -99;

/// [MessageManager] inbound message handler (terminates the message pipeline).
const int messageHandlerPriority = -100;

/// Typical presence extension parsers (caps, MUC).
///
/// Must be greater than [presenceHandlerPriority].
const int presenceExtensionPriority = -99;

/// [PresenceManager] inbound presence handler (terminates the presence pipeline).
const int presenceHandlerPriority = -100;
