%% @doc Answers `mcl-search/web_search': proxies a query to a SearXNG
%% instance's JSON search API (`GET /search?q=...&format=json') and returns a
%% bounded, shaped list of results.
%%
%% SearXNG's base URL is `searxng_url' (SEARXNG_URL in the deploy), with no
%% default: the service does nothing useful without one, so mcl_search_service
%% refuses to start unconfigured. On the fleet it is the SearXNG beside it on
%% the same host network, reached on loopback.
%%
%% Pure OTP for HTTP and JSON (inets/httpc and the stdlib `json' module), no
%% extra dependency. Nothing is kept between calls: no store, no history of
%% what anyone searched.
-module(web_search_responder).
-behaviour(macula_response).

-export([init/1, handle_request/2]).
%% The health probe mcl_search_service:health/0 calls, and the boot check.
-export([searxng_health/0, searxng_url/0]).
%% Exported for mesh-free unit tests.
-export([validate_query/1, clamp_limit/1, decode_results/1, fetch_timeout_ms/0]).

-include_lib("kernel/include/logger.hrl").

-define(DEFAULT_MAX_RESULTS, 10).
-define(HARD_MAX_RESULTS, 25).
-define(MAX_QUERY_BYTES, 512).
%% Longer than SearXNG's own longest wait (`max_request_timeout', 15 s in
%% deploy/searxng-settings.yml and on the fleet): SearXNG answers when its
%% slowest engine does or its timeout ends, and a fetch that gave up first
%% turned every query with one slow engine into search_unavailable. A caller's
%% CALL deadline must allow for it.
-define(FETCH_TIMEOUT, 20000).
-define(CONNECT_TIMEOUT, 5000).
-define(UA, "mcl-search/0.1 (+https://github.com/macula-services/mcl-search)").

init(_Args) ->
    _ = application:ensure_all_started(inets),
    {ok, undefined}.

%% `query' and `limit' are read through mcl_om_wire:field/3, which finds a key
%% in whichever form the frame decoder left it and unwraps a `{text, Bin}'
%% value.
handle_request(Payload, State) ->
    Query = mcl_om_wire:field(query, Payload, <<>>),
    Limit = clamp_limit(mcl_om_wire:field(limit, Payload, ?DEFAULT_MAX_RESULTS)),
    reply_for(validate_query(Query), Query, Limit, State).

reply_for(invalid, _Query, _Limit, State) ->
    {error, invalid_query, State};
reply_for(ok, Query, Limit, State) ->
    replied(searched(Query), Limit, State).

searched(Query) -> decoded(fetch(Query)).

decoded({ok, Body}) -> decode_results(Body);
decoded({error, _} = Failed) -> Failed.

%% A caller learns the search failed; the log says why. A tuple reason would
%% reach the caller with no text at all, since macula carries only a reason it
%% can render as short text.
replied({ok, Results}, Limit, State) ->
    {reply, #{results => lists:sublist(Results, Limit)}, State};
replied({error, Why}, _Limit, State) ->
    ?LOG_WARNING("mcl-search: web_search unavailable: ~p", [Why]),
    {error, search_unavailable, State}.

%% @doc How long a fetch waits for SearXNG.
-spec fetch_timeout_ms() -> pos_integer().
fetch_timeout_ms() -> ?FETCH_TIMEOUT.

%% @doc A blank query would ask SearXNG for everything, and an over-length one
%% is someone testing limits, not searching. Both are refused before any HTTP
%% call is made.
validate_query(<<>>) -> invalid;
validate_query(Query) when is_binary(Query), byte_size(Query) =< ?MAX_QUERY_BYTES -> ok;
validate_query(_Query) -> invalid.

%% @doc A caller's limit is clamped, never trusted: an unbounded one would pull
%% SearXNG's full result set, and every upstream engine query behind it, on
%% every call.
clamp_limit(Limit) when is_integer(Limit), Limit > 0, Limit =< ?HARD_MAX_RESULTS ->
    Limit;
clamp_limit(Limit) when is_integer(Limit), Limit > ?HARD_MAX_RESULTS ->
    ?HARD_MAX_RESULTS;
clamp_limit(_Limit) ->
    ?DEFAULT_MAX_RESULTS.

fetch(Query) -> fetched(searxng_url(), Query).

fetched(undefined, _Query) ->
    {error, searxng_url_unconfigured};
fetched(Base, Query) ->
    QueryString = uri_string:compose_query([{"q", binary_to_list(Query)}, {"format", "json"}]),
    Request = {Base ++ "/search?" ++ QueryString, [{"User-Agent", ?UA}]},
    HTTPOpts = [{timeout, ?FETCH_TIMEOUT}, {connect_timeout, ?CONNECT_TIMEOUT}],
    normalize(httpc:request(get, Request, HTTPOpts, [{body_format, binary}])).

normalize({ok, {{_V, 200, _R}, _H, Body}}) -> {ok, Body};
normalize({ok, {{_V, Code, _R}, _H, _B}})  -> {error, {http, Code}};
normalize({error, Reason})                 -> {error, Reason}.

%% @doc SearXNG's result carries more than a caller needs (engine lists,
%% positions, scores): shaped down to the four fields that let an agent decide
%% whether to follow a result.
decode_results(Body) ->
    try json:decode(Body) of
        #{<<"results">> := Results} when is_list(Results) ->
            {ok, [shape(R) || R <- Results]};
        _Other ->
            {error, unexpected_response_shape}
    catch
        error:_ -> {error, invalid_json}
    end.

%% Every field is prose or a URL a caller reads, so each goes out `{text, Bin}',
%% a CBOR text string. A bare binary is a CBOR byte string, and every non-BEAM
%% caller would receive it as bytes.
shape(R) ->
    #{title   => text(maps:get(<<"title">>, R, <<>>)),
      url     => text(maps:get(<<"url">>, R, <<>>)),
      content => text(maps:get(<<"content">>, R, <<>>)),
      engine  => text(maps:get(<<"engine">>, R, <<>>))}.

text(Bin) when is_binary(Bin) -> {text, Bin}.

%% @doc The configured SearXNG base URL, or `undefined' when there is none.
-spec searxng_url() -> string() | undefined.
searxng_url() -> configured(application:get_env(mcl_search, searxng_url)).

configured({ok, Url}) when is_binary(Url), Url =/= <<>> -> binary_to_list(Url);
configured({ok, [_ | _] = Url}) -> Url;
configured(_Unset) -> undefined.

%% @doc SearXNG's own liveness endpoint, not a real search: this runs on every
%% health poll, and spending an upstream engine query to answer "are you up"
%% would be a self-inflicted denial of service against the thing probed.
-spec searxng_health() -> ok | {degraded, term()}.
searxng_health() ->
    %% A health poll can land before the first search has run init/1.
    _ = application:ensure_all_started(inets),
    probed(searxng_url()).

probed(undefined) ->
    {degraded, searxng_url_unconfigured};
probed(Base) ->
    Request = {Base ++ "/healthz", [{"User-Agent", ?UA}]},
    HTTPOpts = [{timeout, 5000}, {connect_timeout, 3000}],
    health_verdict(httpc:request(get, Request, HTTPOpts, [{body_format, binary}])).

health_verdict({ok, {{_V, 200, _R}, _H, _B}}) -> ok;
health_verdict({ok, {{_V, Code, _R}, _H, _B}}) -> {degraded, {searxng_http, Code}};
health_verdict({error, Reason}) -> {degraded, {searxng_unreachable, Reason}}.
