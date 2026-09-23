%% @doc The service contract, asserted locally.
%%
%% mcl_om resolves its six callbacks BY NAME at startup, on a live node, so a
%% service that forgets one dies with `undef' where nobody is watching. The
%% primary defence is the `-behaviour(mcl_om_service)' attribute on the
%% service module, which turns a missing callback into a compile error under
%% warnings_as_errors.
%%
%% What this suite adds is everything the compiler cannot see: that the attribute
%% has not been quietly dropped, that the values inside those callbacks are the
%% shapes mcl_om will destructure, and that the names and version this service
%% reports are the ones it actually has. Nothing local boots mcl_om, so
%% asserting the shape by hand is the closest available thing to a rehearsal.
-module(mcl_search_service_tests).

-include_lib("eunit/include/eunit.hrl").

-define(APP, mcl_search).
-define(SERVICE, mcl_search_service).

%% Belt and braces with the behaviour attribute, and it survives the attribute
%% being removed. If mcl_om ever adds a SEVENTH required callback this test
%% keeps passing and the deploy still breaks, which is the honest limit of a
%% local assertion about a remote contract.
exports_every_required_callback_test() ->
    _ = code:ensure_loaded(?SERVICE),
    Required = [{info, 0}, {start, 1}, {stop, 1},
                {health, 0}, {capabilities, 0}, {identity_spec, 0}],
    Missing = [F || {N, A} = F <- Required,
                    not erlang:function_exported(?SERVICE, N, A)],
    ?assertEqual([], Missing).

info_carries_the_three_keys_test() ->
    #{name := Name, version := Vsn, description := Desc} = ?SERVICE:info(),
    ?assert(is_binary(Name)),
    ?assert(is_binary(Vsn)),
    ?assert(is_binary(Desc)),
    ?assertEqual(<<"mcl-search">>, Name).

%% THE TWO NAMES MUST AGREE. The OTP application is snake_case because it is an
%% Erlang atom; the repository, the container image and the name this service
%% answers to on the mesh are kebab-case. They describe one service, so a
%% scaffold generated with a mismatched pair is caught here on the first eunit
%% run rather than by a puzzled reader months later.
mesh_name_matches_the_application_test() ->
    #{name := Wire} = ?SERVICE:info(),
    Snake = atom_to_binary(?APP, utf8),
    ?assertEqual(binary:replace(Snake, <<"_">>, <<"-">>, [global]), Wire).

%% The version in info/0 is what a peer reads off /health, so it disagreeing with
%% the application it describes is a lie that nothing else would catch.
info_version_matches_the_application_test() ->
    _ = application:load(?APP),
    {ok, Vsn} = application:get_key(?APP, vsn),
    #{version := Reported} = ?SERVICE:info(),
    ?assertEqual(list_to_binary(Vsn), Reported).

%% health/0 is a real probe of SearXNG, so its verdict depends on whether one
%% is reachable while this runs. Only the shape is asserted here: `ok' or
%% `{degraded, _}', never a crash. test_live/ covers a real SearXNG.
health_returns_the_documented_shape_test() ->
    ?assert(is_documented_health_shape(?SERVICE:health())).

is_documented_health_shape(ok) -> true;
is_documented_health_shape({degraded, _Reason}) -> true;
is_documented_health_shape(_Other) -> false.

%% SEARXNG_URL has no default. A node without one refuses to start rather than
%% boot green and fail every search.
start_refuses_without_a_searxng_url_test() ->
    application:unset_env(?APP, searxng_url),
    ?assertError({searxng_url, unconfigured}, ?SERVICE:start(#{})).

%% One procedure, `mcl-search/web_search' (the org comes from config), answered
%% by a macula_response handler. Its member gate is web_search_member_gate_tests'
%% business. Adding a second procedure breaks this and makes someone write down
%% what the service can now do.
announces_web_search_only_test() ->
    application:set_env(macula, crypto_profile, pq_hybrid),
    application:set_env(mcl_om, realm, binary:copy(<<"ab">>, 32)),
    {ok, Realm} = macula_node_keys:generate(realm, pq_hybrid, #{}),
    application:set_env(mcl_om, realm_key,
                        binary:encode_hex(macula_node_keys:public_key(Realm), lowercase)),
    try
        ?assertMatch([#{name := <<"web_search">>, version := 1,
                        handler := {web_search_responder, []},
                        auth := {realm_member_required, <<_:256>>, <<"member/email-verified">>}}],
                     ?SERVICE:capabilities())
    after
        [application:unset_env(A, K) || {A, K} <- [{macula, crypto_profile}, {mcl_om, realm},
                                                   {mcl_om, realm_key}]]
    end.

identity_spec_has_the_shape_mcl_om_expects_test() ->
    #{scope := Scope, actions := Actions,
      resources := Resources, ttl_days := Ttl} = ?SERVICE:identity_spec(),
    ?assert(is_binary(Scope)),
    ?assert(is_list(Actions)),
    ?assert(is_list(Resources)),
    ?assert(is_integer(Ttl) andalso Ttl > 0).

%% The authority is for topics published and subscribed to, and mcl-search does
%% neither: web_search is a CALL, served under its own D25 provider grant.
asks_the_realm_for_no_topic_authority_test() ->
    #{actions := Actions, resources := Resources} = ?SERVICE:identity_spec(),
    ?assertEqual([], Actions),
    ?assertEqual([], Resources).

%% The supervisor starts and stops cleanly on its own, without mcl_om. It has
%% no children as generated; this asserts the tree is startable, not that it does
%% any work.
supervisor_starts_and_stops_test() ->
    {ok, Pid} = mcl_search_sup:start_link(),
    ?assert(is_process_alive(Pid)),
    ?assertEqual([], supervisor:which_children(Pid)),
    unlink(Pid),
    exit(Pid, shutdown).

%%==============================================================================
%% The runtime is pinned in two places, and neither is the one you are running
%%==============================================================================

%% ⚠ THIS GUARD EXISTS BECAUSE A SIBLING SERVICE DID NOT HAVE IT, AND IT COST
%% THREE COMMITS AND AN IMAGE THAT SHIPPED ANYWAY.
%%
%% Its `Containerfile' said 27 while development ran on 28. So `rebar3 eunit'
%% passing locally meant "passing on 28" and nothing more, CI failed on a crash
%% that does not occur on 28 at all, and because the image build is a separate
%% workflow the image went to the fleet regardless.
%%
%% The release is pinned in TWO files, and the version actually running is a
%% third thing that agrees with neither by default. **A comment in each file
%% saying they must match is not a mechanism**, and both files carried one.
%%
%% ⚠⚠ IT FAILS RATHER THAN WARNS WHEN YOUR VM DIFFERS, AND THAT IS DELIBERATE.
%% Developing on a release you do not ship makes a green suite mean less than it
%% appears to. If you want to work on another release, move both pins and find
%% out what breaks, which is the whole point of having them.
%%
%% ⚠ TO THE PATCH, AND NOTHING FLOATS. This compared majors only, so when Docker
%% Hub moved the floating `erlang:28-alpine' on 2026-09-22 a service generated
%% from this template shipped OTP 28.5 and its guard stayed green. It compares
%% the full release now: the builder's (which must also carry a digest, so a
%% re-pushed tag cannot change what builds), lint's image and the release its
%% toolchain step insists on, .tool-versions, and this VM.
the_runtime_agrees_between_the_image_the_ci_and_this_vm_test() ->
    Image = pinned("Containerfile",
                   "^FROM docker\\.io/(?:hexpm/)?erlang:([0-9]+\\.[0-9]+\\.[0-9]+)"
                   "-alpine[^@\\s]*@sha256:[0-9a-f]{64} AS builder$"),
    CiImage = pinned(".github/workflows/lint.yml",
                     "^\\s+image: docker\\.io/(?:hexpm/)?erlang:([0-9]+\\.[0-9]+\\.[0-9]+)"
                     "[^@\\s]*@sha256:[0-9a-f]{64}$"),
    CiCheck = pinned(".github/workflows/lint.yml",
                     "\\{<<\"([0-9]+\\.[0-9]+\\.[0-9]+)\">>, true\\} -> halt\\(0\\);"),
    Tools = pinned(".tool-versions", "^erlang ([0-9]+\\.[0-9]+\\.[0-9]+)$"),
    %% Sorted and deduplicated, so a failure prints every version rather than
    %% the first pair that happened to be compared.
    ?assertEqual([Image], lists:usort([Image, CiImage, CiCheck, Tools, running_otp()])).

%% The full release, 28.4.3 and not 28: `otp_release' names only the major.
running_otp() ->
    {ok, Version} = file:read_file(filename:join([code:root_dir(), "releases",
                                                  erlang:system_info(otp_release),
                                                  "OTP_VERSION"])),
    string:trim(Version).

pinned(Relative, Pattern) ->
    {ok, Text} = file:read_file(alongside(Relative)),
    {match, [Version]} = re:run(Text, Pattern,
                                [multiline, {capture, all_but_first, binary}]),
    Version.

%% Relative to the beam rather than the working directory, because eunit runs
%% from wherever the developer happens to be standing.
alongside(Name) -> climb(filename:dirname(code:which(?MODULE)), Name, 8).

climb(_Dir, Name, 0) -> Name;
climb(Dir, Name, Left) ->
    Candidate = filename:join(Dir, Name),
    found(filelib:is_regular(Candidate), Candidate, Dir, Name, Left).

found(true, Candidate, _Dir, _Name, _Left) -> Candidate;
found(false, _Candidate, Dir, Name, Left) ->
    climb(filename:dirname(Dir), Name, Left - 1).
