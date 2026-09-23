# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Web search for realm members on macula 12 and `mcl_om` 0.26.6: one procedure,
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
