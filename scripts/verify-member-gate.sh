#!/usr/bin/env bash
# Prove mcl-search/web_search's member gate on the live mesh, from the
# caller's side, with macula-cli. Six calls, in this order:
#
#   b. under REALM, no token                                            -> unauthorized
#   a. under OTHER_REALM, a realm this service does not serve           -> unknown_next_peer
#   c. under REALM, a member token signed by another realm's key        -> unauthorized
#   d. under REALM, a genuine member token presented by another caller  -> unauthorized
#   e. under REALM, a device-tier token from the realm                  -> unauthorized
#   f. under REALM, a member presenting its own email-verified token    -> served
#
# b runs first because an unauthorized reply proves the service is reachable;
# without that, a's "nothing found" would also pass against a service that is
# simply down, so a is reported INCONCLUSIVE then. f passes only on a real
# result (ok true): an error past the gate, whether a SearXNG outage or a crash,
# carries a BOLT#4 name that does not say which, so it fails f and is printed.
# Run f against a node with a reachable SearXNG. Prints each verdict with the
# BOLT#4 name only; never prints a token. A check whose inputs are unset is
# SKIPPED, never passed.
#
# Environment:
#   STATION           station to call through, host:port
#   REALM             64-hex realm tag the service advertises under
#   OTHER_REALM       64-hex realm tag it does not serve (default: io.macula's)
#   MEMBER_IDENTITY   macula-cli identity seed of the member caller
#   OTHER_IDENTITY    macula-cli identity seed of a second caller
#   MEMBER_UCAN       the member's own email-verified token (d and f)
#   OTHER_REALM_UCAN  a member token for MEMBER_IDENTITY signed by another realm key (c)
#   DEVICE_UCAN       a device-tier token for MEMBER_IDENTITY from REALM (e)
#   MACULA_CLI        macula-cli binary (default: macula-cli on PATH)
#
# usage: scripts/verify-member-gate.sh
set -uo pipefail

: "${STATION:?set STATION to host:port}"
: "${REALM:?set REALM to the 64-hex realm tag}"
: "${MEMBER_IDENTITY:?set MEMBER_IDENTITY to the identity seed of the member caller}"
OTHER_REALM=${OTHER_REALM:-ABB81B5A614B63551B400B810648C0C8A78EFAD845442630C94B46CC95D2FCD1}
OTHER_IDENTITY=${OTHER_IDENTITY:-}
MEMBER_UCAN=${MEMBER_UCAN:-}
OTHER_REALM_UCAN=${OTHER_REALM_UCAN:-}
DEVICE_UCAN=${DEVICE_UCAN:-}
CLI=${MACULA_CLI:-macula-cli}
failures=0

# outcome <realm> <identity seed> [token file] -> served | <bolt4 name> | unparsable
outcome() {
  local args=(call -json -timeout "${TIMEOUT:-20s}" -realm "$1" -identity "$2"
              -args '{"query":"member gate check","limit":1}')
  [ -n "${3:-}" ] && args+=(-ucan "$3")
  "$CLI" "${args[@]}" "$STATION" mcl-search/web_search 2>/dev/null \
    | python3 -c '
import json, sys
try:
    reply = json.load(sys.stdin)
except Exception:
    print("unparsable"); sys.exit()
error = reply.get("error") or {}
print("served" if reply.get("ok") else error.get("bolt4_name") or "error")'
}

# verdict <label> <expected: served | a BOLT#4 name> <actual>
verdict() {
  local pass=false
  [ "$2" = "$3" ] && pass=true
  if $pass; then echo "PASS $1: $3"; else echo "FAIL $1: expected $2, got $3"; failures=$((failures + 1)); fi
}

skip() { echo "SKIPPED $1: $2"; }

echo "=== member gate via $STATION at $(date -u +%FT%TZ), realm ${REALM:0:8}..${REALM: -4}"

b=$(outcome "$REALM" "$MEMBER_IDENTITY")
verdict "b no token" unauthorized "$b"

a=$(outcome "$OTHER_REALM" "$MEMBER_IDENTITY" "$MEMBER_UCAN")
if [ "$b" = unauthorized ]; then
  verdict "a other realm" unknown_next_peer "$a"
else
  echo "INCONCLUSIVE a other realm: got $a, but b did not show the service reachable"
  failures=$((failures + 1))
fi

if [ -n "$OTHER_REALM_UCAN" ]; then
  verdict "c another realm's token" unauthorized "$(outcome "$REALM" "$MEMBER_IDENTITY" "$OTHER_REALM_UCAN")"
else
  skip "c another realm's token" "OTHER_REALM_UCAN unset"
fi

if [ -n "$OTHER_IDENTITY" ] && [ -n "$MEMBER_UCAN" ]; then
  verdict "d someone else's token" unauthorized "$(outcome "$REALM" "$OTHER_IDENTITY" "$MEMBER_UCAN")"
else
  skip "d someone else's token" "OTHER_IDENTITY or MEMBER_UCAN unset"
fi

if [ -n "$DEVICE_UCAN" ]; then
  verdict "e device tier" unauthorized "$(outcome "$REALM" "$MEMBER_IDENTITY" "$DEVICE_UCAN")"
else
  skip "e device tier" "DEVICE_UCAN unset"
fi

if [ -n "$MEMBER_UCAN" ]; then
  verdict "f member's own token" served "$(outcome "$REALM" "$MEMBER_IDENTITY" "$MEMBER_UCAN")"
else
  skip "f member's own token" "MEMBER_UCAN unset"
fi

echo "=== $failures failure(s)"
[ "$failures" -eq 0 ]
