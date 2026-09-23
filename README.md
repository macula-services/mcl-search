# mcl-search

**Web search over the live internet for realm members, backed by SearXNG**

## What it does

One procedure, `mcl-search/web_search`, served only to email-verified members
of the realm. It proxies a query to a SearXNG instance's JSON API and hands back
a bounded, shaped list of results:

| Payload | Reply |
|---------|-------|
| `query` (required, 1 to 512 bytes), `limit` (optional, default 10, capped at 25) | `results`: a list of `title`, `url`, `content`, `engine`, each CBOR text |

SearXNG answers when its slowest engine does, up to its own
`max_request_timeout` (15 s), so a search can take that long and the service
waits up to 20 s for it. Give the CALL a deadline of 25 s or more.

A refusal comes back as the call's error: `invalid_query` for a blank, missing
or over-long query, `search_unavailable` when SearXNG cannot answer (the reason
goes to the service's log), and `unauthorized`, from macula itself, for a caller
who is not a member.

It keeps no store and no record of what anyone searched, by design.

### Who may search

`web_search` spends this node's SearXNG on the live internet, so it serves a
caller only when the CALL carries a membership token signed by the realm's
signing key, for that caller's own identity, at the `member/email-verified`
tier. macula checks the token on every inbound call before the handler runs.
The device tier (`member/device-verified`) is refused: the realm mints it to any
device that proves it holds its own key.

The realm key the gate names is `MCL_REALM_KEY`, the same key the pool pins as
its trust anchor, because macula-realm signs its member tokens with it. There is
nothing extra to configure, and without a valid key the node refuses to boot:
there is no open fallback.

`scripts/verify-member-gate.sh` proves the gate on the live mesh with
`macula-cli`: a call with no token, another realm's token, somebody else's token
or a device-tier token is refused, and a member presenting its own token is
served. It prints verdicts and BOLT#4 names only, never a token, and its header
lists the environment it reads.

### SearXNG, the one dependency

This service does nothing without a SearXNG instance, named by `SEARXNG_URL`.
There is no default anywhere: a node without it refuses to start, and `/health`
reports `degraded` whenever SearXNG does not answer its `/healthz`.

On the fleet, SearXNG runs on **beam03** (container `searxng`, host network,
`127.0.0.1:8888`). Loopback reaches it only from the same host, so mcl-search
runs beside it there with `SEARXNG_URL=http://127.0.0.1:8888`, or points at
another instance deliberately.

For local development:

```sh
podman run -d --name searxng-dev -p 127.0.0.1:8888:8080 \
  --pids-limit=4096 --ulimit nproc=4096:4096 \
  -v "$PWD/deploy/searxng-settings.yml:/etc/searxng/settings.yml:ro" \
  docker.io/searxng/searxng:latest
```

`deploy/searxng-settings.yml` turns on the JSON format the service asks for.

## Running it

    rebar3 compile
    rebar3 eunit                           # no SearXNG needed
    rebar3 lint
    rebar3 dialyzer
    SEARXNG_URL=http://127.0.0.1:8888 \
      rebar3 as live_test eunit --dir test_live   # against the SearXNG above

    scripts/health.sh                      # against a running node

Building the image needs a Rust toolchain, because macula ships a QUIC NIF and
the alpine build compiles it from source rather than fetching one linked against
a different libc.

    podman build -t mcl-search -f Containerfile .

## Configuration

| Variable | Default | Meaning |
|----------|---------|---------|
| `MCL_REALM` | required | 64-hex realm tag, the `sha256` of the realm's name. No default: a service that guesses its realm announces itself where nobody can attribute it. |
| `MCL_REALM_KEY` | required | The realm's public signing key, hex encoded: the **trust anchor**, not an identifier. Every org-namespaced advertisement is verified against it, so without it nothing resolves, the boot claim never reaches the realm, and the service stays green while unreachable. Public material, not a secret. |
| `MACULA_STATION_SEEDS` | required | Station hosts to dial, `host[:port]`, comma-separated. No default: naming a realm costs nothing, dialling a production station from every dev clone does. |
| `MACULA_STATION_NODE_IDS` | required | The matching 64-hex station node ids, comma-separated, index-paired with the seeds. The dial is pinned (D5): mcl_om refuses to boot a pool with an unpinned seed. |
| `MCL_SERVICE_NAME` | `mcl-search` | Label on the boot claim the realm's operator sees on the Providers desk. Falls back to the service's own name. |
| `MCL_BOX` | empty | Label naming the host, also on the boot claim. Set it where you deploy (on the fleet, `beam03`). |
| `MCL_HEALTH_PORT` | `8497` | Health endpoint, on 127.0.0.1 only. Host networking makes a collision a silent bind failure, so check the host before changing.  |
| `MCL_NODE_NAME` | `mcl_search` | Erlang node name. |
| `MCL_NODE_HOST` | `127.0.0.1` | Erlang node host. |
| `MCL_COOKIE` | `mcl_search` | Erlang cookie. |
| `SEARXNG_URL` | required | SearXNG's base URL, e.g. `http://127.0.0.1:8888`. No default: without it the node refuses to start. |

`deploy/docker-compose.yml` runs it, and carries what the service knows about
itself. If you deploy through something else, let that carry **placement**: which
host, which station, which realm, which secret store. Keeping the two apart is
what stops a config table in a README and the real environment drifting.

## Deployment

The image has two channels. A push to `main` publishes
`ghcr.io/macula-services/mcl-search:latest`, the deploy channel: a host that follows
`:latest` deploys every merge. A `v*` tag publishes its own version and nothing
else, the rollback archive: pin a host to one to roll back. A push that changes
only documentation builds no image (`scripts/is_image_push.sh`).

The service's org, the `<org>` in every procedure it offers (`<org>/<name>`), is
this repository's name, fixed in `config/sys.config.src`. The realm's grant names
it; without an org mcl_om advertises nothing.

Two things CI cannot do for you, both of which have bitten:

1. The registry package may be created **private**, and the pull then fails on
   the host with a bare `unauthorized` that names nothing. Check it after the
   first build. On ghcr the `org.opencontainers.image.source` label in the
   Containerfile is what links the package to the repository.
2. The host needs `MCL_REALM` and the pinned station pair supplied from
   somewhere they are not committed.

## The service contract

Six callbacks in `mcl_search_service`, all required, all resolved **by name** by
`mcl_om` at startup on a live node. The `-behaviour(mcl_om_service)`
attribute turns a missing one into a compile error rather than an `undef` where
nobody is watching, and the eunit suite guards the attribute itself.

### Adding a store later

This service has no `reckon-db` store, which is the right answer for most. The
reckon-db applications run either way; what a store adds is a data directory, an
open handle, and something written.

The cheapest way to get one is to scaffold again with `store=1`, which generates
the callbacks, the config and the guards together.

⚠ **By hand it is three things and not one, and the missing third crash-loops the
node.** Export `store_id/0` and `data_dir/0`; add the `evoq` adapter block to
`config/sys.config.src`, without which boot raises
`{not_configured, event_store_adapter}` before any service code runs; and mount a
volume in the compose file. A sibling service put two of three fleet nodes into a
boot loop by doing the first and not the second.

## Licence

Apache-2.0.
