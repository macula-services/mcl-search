%% @doc Live proof against a real, running SearXNG: health answers, a real
%% query comes back shaped, the limit holds.
%%
%% It calls the responder in-process, so it never serializes a reply through
%% macula's CBOR encoder: it proves the shape handed to macula, not the bytes a
%% remote caller receives. web_search_member_gate_tests covers the codec path
%% for the gate; a real mesh_call covers the rest.
%%
%% Not part of `rebar3 eunit' or CI: a SearXNG blip, or a runner with none
%% reachable, must not block a change. Run it against a real instance
%% (SEARXNG_URL, default http://127.0.0.1:8888, the fleet's own address on the
%% SearXNG host):
%%   rebar3 as live_test eunit --dir test_live
-module(web_search_live_tests).

-include_lib("eunit/include/eunit.hrl").

-define(H, web_search_responder).

setup() ->
    _ = application:load(mcl_search),
    Url = os:getenv("SEARXNG_URL", "http://127.0.0.1:8888"),
    ok = application:set_env(mcl_search, searxng_url, Url),
    {ok, _} = application:ensure_all_started(inets),
    Url.

web_search_live_test_() ->
    {timeout, 20, fun run/0}.

run() ->
    Url = setup(),
    verify_health(Url),
    verify_a_real_query_returns_real_results(),
    verify_the_limit_is_honored(),
    verify_an_invalid_query_is_rejected_before_any_http_call().

%% Not `ok' means no SearXNG is reachable at Url.
verify_health(Url) ->
    ?assertEqual({Url, ok}, {Url, ?H:searxng_health()}).

%% A genuine query against a genuine SearXNG, asserting the shape promised, not
%% any result's content: which engine answers is the live internet's business.
%% The query arrives `{text, Bin}'-tagged, as it does off the wire.
verify_a_real_query_returns_real_results() ->
    Payload = #{query => {text, <<"erlang programming language">>}, limit => 5},
    {reply, #{results := Results}, _State} = ?H:handle_request(Payload, undefined),
    ?assert(length(Results) > 0),
    ?assert(length(Results) =< 5),
    lists:foreach(fun assert_result_shape/1, Results).

assert_result_shape(#{title := Title, url := Url, content := Content, engine := Engine}) ->
    ?assertMatch({text, B} when is_binary(B), Title),
    ?assertMatch({text, B} when is_binary(B), Url),
    ?assertMatch({text, B} when is_binary(B), Content),
    ?assertMatch({text, B} when is_binary(B), Engine),
    %% A real hit always has a url: an empty one means SearXNG's response
    %% shape drifted, which a synthetic fixture would never show.
    ?assertNotEqual({text, <<>>}, Url).

verify_the_limit_is_honored() ->
    Payload = #{query => {text, <<"erlang">>}, limit => 1},
    {reply, #{results := Results}, _State} = ?H:handle_request(Payload, undefined),
    ?assertEqual(1, length(Results)).

verify_an_invalid_query_is_rejected_before_any_http_call() ->
    ?assertEqual({error, invalid_query, undefined},
                 ?H:handle_request(#{query => {text, <<>>}}, undefined)).
