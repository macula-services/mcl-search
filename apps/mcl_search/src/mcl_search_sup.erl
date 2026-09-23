%% @doc Supervises this service's own processes.
%%
%% NO CHILDREN. macula_response spawns a responder per call, and nothing is
%% kept between calls, so the service itself has nothing to run.
-module(mcl_search_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, []}}.
