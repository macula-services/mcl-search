%% @doc The mcl_om service contract for mcl-search.
%%
%% Web search over the live internet, for realm members, backed by SearXNG.
%% One request-and-reply procedure, `mcl-search/web_search', gated to
%% email-verified members of the realm (see web_search_member_gate). No store:
%% it keeps no record of what anyone searched.
%%
%% SIX CALLBACKS, ALL REQUIRED. mcl_om resolves them BY NAME at startup, on a
%% live node, so a service that forgets one dies with `undef' where nobody is
%% watching. The `-behaviour' attribute below is what turns that into a compile
%% error instead, and the test suite guards the attribute itself.
-module(mcl_search_service).

-behaviour(mcl_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).

info() ->
    #{name => <<"mcl-search">>,
      version => <<"0.1.0">>,
      description => <<"Web search over the live internet for realm members, backed by SearXNG">>}.

%% SEARXNG_URL has no default: a node without one refuses to start rather than
%% boot green and fail every search.
start(_Opts) ->
    searxng_configured(web_search_responder:searxng_url()),
    mcl_search_sup:start_link().

searxng_configured(undefined) -> erlang:error({searxng_url, unconfigured});
searxng_configured(_Url) -> ok.

stop(_State) -> ok.

%% A real probe: the service does one thing, answer web searches, and cannot do
%% it with no SearXNG behind it. `{degraded, _}' rather than `{down, _}': the
%% mesh side is fine, only the one thing it exists for is unavailable.
health() -> web_search_responder:searxng_health().

%% WHAT THIS SERVICE ANNOUNCES IT CAN DO, AND FOR WHOM. The member policy raises
%% when the realm key is missing or malformed, and mcl_om:boot/1 calls this
%% before advertising or starting anything, so such a node does not boot.
capabilities() ->
    [#{name => <<"web_search">>, version => 1,
       handler => {web_search_responder, []},
       auth => web_search_member_gate:policy()}].

%% THE AUTHORITY THIS SERVICE ASKS THE REALM FOR, and deliberately nothing more.
%% Ask for exactly the topics you publish and subscribe to. mcl-search publishes
%% and subscribes to none: web_search is a CALL, served under its own D25
%% provider grant, so it asks for nothing.
%%
%% The scope is claimed now because it is the namespace every later resource
%% hangs under, and a scope costs nothing while a rename costs every deployed
%% peer.
identity_spec() ->
    #{scope => <<"mcl-search">>,
      actions => [],
      resources => [],
      ttl_days => 30}.
