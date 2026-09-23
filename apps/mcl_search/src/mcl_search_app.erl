%% @doc OTP application entry.
%%
%% mcl_om:boot/1 wires the mesh, the realm identity and health, advertises
%% web_search under its member policy, then starts this service. Storeless.
-module(mcl_search_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) -> mcl_om:boot(mcl_search_service).

stop(_State) -> ok.
