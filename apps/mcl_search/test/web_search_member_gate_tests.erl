%%% @doc Only email-verified members of the configured realm may search, proven
%%% through the path a real call takes.
%%%
%%% Each case signs a CALL with a caller's identity key and the token under
%%% test, ENCODES it with macula_frame, DECODES the bytes back, verifies the
%%% request, and authorizes what came out of the decoder against the policy
%%% mcl_search_service:capabilities/0 advertises, the same
%%% macula_ucan:authorize/3 call macula_station_link makes before any handler
%%% runs. A hand-built request map would skip the codec, and the codec is where
%%% a text-versus-bytes surprise lives.
-module(web_search_member_gate_tests).

-include_lib("eunit/include/eunit.hrl").

-define(PROFILE, pq_hybrid).
-define(REALM_NAME, <<"io.macula">>).
-define(PROCEDURE, <<"mcl-search/web_search">>).
-define(MEMBER, <<"member/email-verified">>).
-define(DEVICE, <<"member/device-verified">>).

gate_test_() ->
    {setup, fun configure_realm/0, fun unconfigure/1,
     fun(#{realm_key := RealmKey}) ->
         Member = identity(),
         Other = identity(),
         Foreign = realm_key(),
         [{"a member presenting its own email-verified token is served",
           ?_assertMatch({ok, _}, verdict(Member, token(RealmKey, Member, ?MEMBER)))},
          {"a caller with no token is refused",
           ?_assertEqual(unauthorized, verdict(Member, none))},
          {"a device-tier token from the same realm key is refused",
           ?_assertEqual({error, missing_capability},
                         verdict(Member, token(RealmKey, Member, ?DEVICE)))},
          {"a member token signed by another realm's key is refused",
           ?_assertEqual({error, not_the_issuer},
                         verdict(Member, token(Foreign, Member, ?MEMBER)))},
          {"a genuine member token presented by someone else is refused",
           ?_assertEqual({error, not_the_audience},
                         verdict(Other, token(RealmKey, Member, ?MEMBER)))}]
     end}.

%% The policy's realm key id comes from mcl_om's own realm_key, the same
%% realm_trust pin the pool connects with, so there is one copy to configure.
the_gate_names_the_realm_key_the_pool_pins_test_() ->
    {setup, fun configure_realm/0, fun unconfigure/1,
     fun(#{realm_key := RealmKey}) ->
         ?_assertEqual({realm_member_required, macula_node_keys:key_id(RealmKey), ?MEMBER},
                       policy())
     end}.

%% THERE IS NO OPEN FALLBACK. Without a usable realm key the capability list
%% raises, and mcl_om:boot/1 asks for it before advertising or starting
%% anything, so such a node does not come up serving the whole mesh.
no_realm_key_no_capability_test() ->
    application:set_env(macula, crypto_profile, ?PROFILE),
    application:set_env(mcl_om, realm, realm_hex()),
    application:unset_env(mcl_om, realm_key),
    try ?assertError(_, mcl_search_service:capabilities())
    after unconfigure(#{})
    end.

%%--------------------------------------------------------------------

configure_realm() ->
    RealmKey = realm_key(),
    application:set_env(macula, crypto_profile, ?PROFILE),
    application:set_env(mcl_om, realm, realm_hex()),
    application:set_env(mcl_om, realm_key,
                        binary:encode_hex(macula_node_keys:public_key(RealmKey), lowercase)),
    #{realm_key => RealmKey}.

unconfigure(_) ->
    [application:unset_env(A, K) || {A, K} <- [{macula, crypto_profile}, {mcl_om, realm},
                                               {mcl_om, realm_key}]],
    ok.

realm_hex() -> binary:encode_hex(realm_id(), lowercase).

realm_id() -> crypto:hash(sha256, ?REALM_NAME).

realm_key() ->
    {ok, Key} = macula_node_keys:generate(realm, ?PROFILE, #{}),
    Key.

identity() ->
    {ok, Key} = macula_node_keys:generate(identity, ?PROFILE, #{puzzle_difficulty => 0}),
    Key.

policy() ->
    [#{name := <<"web_search">>, auth := Policy}] = mcl_search_service:capabilities(),
    Policy.

token(Issuer, Holder, Can) ->
    {ok, Audience} = macula_node_keys:node_id(Holder),
    macula_ucan:create(Issuer, Audience,
                       [#{with => <<"mri:realm:", ?REALM_NAME/binary>>, can => Can}],
                       #{exp => erlang:system_time(second) + 3600}).

%% Sign, encode, decode, verify, then authorize the decoded request exactly as
%% macula_station_link does. A request that decodes with no token at all is the
%% station link's `unauthorized'.
verdict(Caller, Token) ->
    Frame = macula_frame:call(with_token(Token, #{request_id => crypto:strong_rand_bytes(16),
                                                  realm => realm_id(),
                                                  procedure => ?PROCEDURE,
                                                  target => crypto:strong_rand_bytes(32),
                                                  deadline => erlang:system_time(millisecond) + 30_000,
                                                  payload => #{query => {text, <<"erlang">>}}}),
                              Caller),
    {ok, Decoded, <<>>} = macula_frame:decode(macula_frame:encode(Frame)),
    {ok, Request} = macula_frame:verify_request(Decoded, ?PROFILE),
    authorized(policy(), Request).

with_token(none, Spec) -> Spec;
with_token(Token, Spec) -> Spec#{token => Token}.

authorized(Policy, #{token := Token, caller := Caller, realm := Realm, procedure := Procedure})
  when is_binary(Token) ->
    macula_ucan:authorize(Token, Policy, #{caller => Caller, profile => ?PROFILE,
                                           now => erlang:system_time(second),
                                           realm => Realm, procedure => Procedure,
                                           proofs => #{}});
authorized(_Policy, _RequestWithoutToken) ->
    unauthorized.
