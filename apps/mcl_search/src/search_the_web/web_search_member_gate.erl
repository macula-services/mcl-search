%% @doc Who may search: email-verified members of this service's realm.
%%
%% web_search spends this node's SearXNG on the live internet, so it serves a
%% caller only when the CALL carries a membership token signed by the realm's
%% signing key, for that caller's own identity, at the `member/email-verified'
%% tier. macula enforces the policy on every inbound call before the handler
%% runs; this module only builds it.
%%
%% The realm key is the one the pool already pins as `realm_trust'
%% (MCL_REALM_KEY): macula-realm signs its member tokens with that same key, and
%% the policy names it by its key id. One configured value, so the gate and the
%% trust anchor cannot drift apart. It is read through mcl_om's own
%% realm_trust_opts/0, which refuses a missing or malformed key by name, so a
%% node without one raises here, at capabilities/0, before anything is
%% advertised. There is no open fallback.
%%
%% Not `member/device-verified': the realm mints that to any device that proves
%% it holds its own key, so accepting it would let anyone enrol themselves.
-module(web_search_member_gate).

-export([policy/0]).

-define(MEMBER_TIER, <<"member/email-verified">>).

-spec policy() -> {realm_member_required, <<_:256>>, binary()}.
policy() ->
    #{realm_trust := Trust} = mcl_om_identity:realm_trust_opts(),
    [RealmKey] = maps:values(Trust),
    {ok, Profile} = macula_crypto_profile:configured(),
    {realm_member_required, macula_node_keys:key_id(RealmKey, Profile), ?MEMBER_TIER}.
