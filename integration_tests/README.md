# Integration Tests

The included `./prosody.cfg.lua` config file must be used for the local Prosody
tests. Ensure that a user `testuser@localhost` with the password `abc123`
exists. Note that this currently requires prosody-trunk.

`badxmpp_certificate_test.dart` and `failure_reconnection_test.dart` talk to
`badxmpp.eu` instead of that local server.
