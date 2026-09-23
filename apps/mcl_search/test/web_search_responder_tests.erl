%% @doc Pure-function coverage for web_search_responder: no mesh, no HTTP, no
%% SearXNG. The live round trip against a real SearXNG is in test_live/.
-module(web_search_responder_tests).

-include_lib("eunit/include/eunit.hrl").

-define(H, web_search_responder).

%%====================================================================
%% validate_query/1
%%====================================================================

validate_query_rejects_empty_test() ->
    ?assertEqual(invalid, ?H:validate_query(<<>>)).

validate_query_accepts_a_normal_query_test() ->
    ?assertEqual(ok, ?H:validate_query(<<"macula mesh routing">>)).

validate_query_rejects_an_oversized_query_test() ->
    Oversized = binary:copy(<<"a">>, 513),
    ?assertEqual(invalid, ?H:validate_query(Oversized)).

validate_query_accepts_exactly_the_byte_cap_test() ->
    AtCap = binary:copy(<<"a">>, 512),
    ?assertEqual(ok, ?H:validate_query(AtCap)).

validate_query_rejects_a_non_binary_test() ->
    ?assertEqual(invalid, ?H:validate_query(not_a_binary)).

%%====================================================================
%% clamp_limit/1
%%====================================================================

clamp_limit_passes_through_a_reasonable_value_test() ->
    ?assertEqual(5, ?H:clamp_limit(5)).

clamp_limit_caps_an_oversized_request_test() ->
    ?assertEqual(25, ?H:clamp_limit(1000)).

clamp_limit_defaults_a_zero_or_negative_value_test() ->
    ?assertEqual(10, ?H:clamp_limit(0)),
    ?assertEqual(10, ?H:clamp_limit(-3)).

clamp_limit_defaults_a_non_integer_test() ->
    ?assertEqual(10, ?H:clamp_limit(<<"5">>)),
    ?assertEqual(10, ?H:clamp_limit(undefined)).

%%====================================================================
%% decode_results/1
%%====================================================================

decode_results_shapes_a_real_looking_response_test() ->
    Body = <<"{\"results\":[",
             "{\"title\":\"Erlang\",\"url\":\"https://erlang.org\",",
             "\"content\":\"A language\",\"engine\":\"duckduckgo\",",
             "\"extra_field_ignored\":true}",
             "]}">>,
    {ok, [Result]} = ?H:decode_results(Body),
    %% Tagged {text, Bin} on the way out: a bare binary is a CBOR byte string,
    %% which every non-BEAM caller receives as bytes.
    ?assertEqual(#{title => {text, <<"Erlang">>}, url => {text, <<"https://erlang.org">>},
                   content => {text, <<"A language">>}, engine => {text, <<"duckduckgo">>}},
                 Result).

decode_results_defaults_missing_fields_test() ->
    Body = <<"{\"results\":[{}]}">>,
    {ok, [Result]} = ?H:decode_results(Body),
    ?assertEqual(#{title => {text, <<>>}, url => {text, <<>>},
                   content => {text, <<>>}, engine => {text, <<>>}},
                 Result).

decode_results_handles_an_empty_result_set_test() ->
    ?assertEqual({ok, []}, ?H:decode_results(<<"{\"results\":[]}">>)).

decode_results_rejects_malformed_json_test() ->
    ?assertEqual({error, invalid_json}, ?H:decode_results(<<"not json at all">>)).

decode_results_rejects_a_response_with_no_results_field_test() ->
    ?assertEqual({error, unexpected_response_shape},
                 ?H:decode_results(<<"{\"other\":1}">>)).

%%====================================================================
%% handle_request/2 refusals, before any HTTP call
%%====================================================================

%% A query arrives `{text, Bin}'-tagged off the wire. A blank or missing one is
%% refused as invalid_query without asking SearXNG anything.
a_blank_or_missing_query_is_refused_before_any_fetch_test() ->
    ?assertEqual({error, invalid_query, undefined},
                 ?H:handle_request(#{query => {text, <<>>}}, undefined)),
    ?assertEqual({error, invalid_query, undefined}, ?H:handle_request(#{}, undefined)).

%% With SearXNG unreachable the call fails as search_unavailable, an atom
%% macula carries as the call's error text; the reason why goes to the log.
an_unreachable_searxng_is_search_unavailable_test() ->
    application:set_env(mcl_search, searxng_url, "http://127.0.0.1:1"),
    try
        ?assertEqual({error, search_unavailable, undefined},
                     ?H:handle_request(#{query => {text, <<"erlang">>}}, undefined)),
        ?assertMatch({degraded, {searxng_unreachable, _}}, ?H:searxng_health())
    after
        application:unset_env(mcl_search, searxng_url)
    end.

%%====================================================================
%% The fetch outlasts SearXNG's own wait
%%====================================================================

%% SearXNG answers once its slowest engine replies or its own timeout ends, up
%% to `max_request_timeout'. A fetch that gives up first turns every query with
%% one slow engine into search_unavailable, and that is exactly what happened
%% against the fleet's SearXNG, which took 10.0 s per such query against a 10 s
%% fetch. The fetch must outlast SearXNG's longest wait, with room to send the
%% reply.
the_fetch_outlasts_searxngs_longest_wait_test() ->
    {ok, Text} = file:read_file(alongside("deploy/searxng-settings.yml")),
    {match, [Max]} = re:run(Text, "^\\s*max_request_timeout:\\s*([0-9.]+)",
                            [multiline, {capture, all_but_first, list}]),
    SearxngMs = round(list_to_float(Max) * 1000),
    ?assert(?H:fetch_timeout_ms() >= SearxngMs + 5000).

alongside(Name) -> climb(filename:dirname(code:which(?MODULE)), Name, 8).

climb(_Dir, Name, 0) -> Name;
climb(Dir, Name, Left) ->
    Candidate = filename:join(Dir, Name),
    found(filelib:is_regular(Candidate), Candidate, Dir, Name, Left).

found(true, Candidate, _Dir, _Name, _Left) -> Candidate;
found(false, _Candidate, Dir, Name, Left) -> climb(filename:dirname(Dir), Name, Left - 1).
