# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **The team image pair.** Builds in `macula-ci-otp` and runs on
  `macula-pq-runtime` (Debian trixie), both pinned by dated tag and digest,
  instead of the scaffold's Alpine pair, whose runtime tag `alpine:3.22`
  floated. CI runs in the same build image; a test holds the three digests and
  the OTP release checks.

### Added

- **On `mcl_om` 0.28 with macula 12.2.** The service answers `mcl-search/info`,
  which mcl_om adds (public facts: versions, labels, health word, procedures),
  and a test sends that reply through macula's frame codec and checks it names
  this service and the mcl_om 0.28 / macula 12.2 pair. 0.28 is the release
  macula 12.2 needs: under 12.2 an older mcl_om lets a failed publish
  announcement kill the publishing process.
- Web search for realm members on macula 12 and `mcl_om` 0.27: one procedure,
  `mcl-search/web_search`, proxied to SearXNG, results as CBOR text.
- The member gate: `{realm_member_required, KeyId, <<"member/email-verified">>}`,
  with the key id derived from `MCL_REALM_KEY`, the realm's own signing key the
  pool already pins. No separate realm-key setting, no open fallback.
- `SEARXNG_URL` is required; the node refuses to start without it, and
  `/health` (bound to 127.0.0.1) reports `degraded` when SearXNG does not answer.
- Refusals `invalid_query` and `search_unavailable` as the call's error.
- A gate test that signs, encodes, decodes and verifies a real CALL before
  authorizing it; a live test against a real SearXNG; the member-gate script.
- CI runs `rebar3 dialyzer` beside lint and eunit.
- The boot claim carries `MCL_SERVICE_NAME` and `MCL_BOX`, which the realm's
  Providers desk shows.
