%% -------------------------------------------------------------------
%%
%% riak_kv_mapreduce: convenience functions for defining common map/reduce phases
%%
%% Copyright (c) 2007-2010 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

%% @doc Convenience functions for defining common map/reduce phases.
-module(riak_kv_mapreduce).

%% phase spec producers
-export([map_identity/1,
         map_object_value/1,
         map_object_value_list/1]).
-export([reduce_identity/1,
         reduce_set_union/1,
         reduce_sort/1,
         reduce_string_to_integer/1,
         reduce_sum/1,
         reduce_plist_sum/1,
         reduce_count_inputs/1]).

%% phase function definitions
-export([map_identity/3,
         map_object_value/3,
         map_object_value_list/3]).
-export([reduce_identity/2,
         reduce_set_union/2,
         reduce_sort/2,
         reduce_string_to_integer/2,
         reduce_sum/2,
         reduce_plist_sum/2,
         reduce_count_inputs/2]).
-export([reduce_index_identity/2,
         reduce_index_extractinteger/2,
         reduce_index_byrange/2,
         reduce_index_regex/2,
         reduce_index_max/2]).

-type keep() :: all|this.

%-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
%-endif.

%%
%% Map Phases
%%

%% @spec map_identity(boolean()) -> map_phase_spec()
%% @doc Produces a spec for a map phase that simply returns
%%      each object it's handed.  That is:
%%      riak_kv_mrc_pipe:mapred(BucketKeys, [map_identity(true)]).
%%      Would return all of the objects named by BucketKeys.
map_identity(Acc) ->
    {map, {modfun, riak_kv_mapreduce, map_identity}, none, Acc}.

%% @spec map_identity(riak_object:riak_object(), term(), term()) ->
%%                   [riak_object:riak_object()]
%% @doc map phase function for map_identity/1
map_identity(RiakObject, _, _) -> [RiakObject].

%% @spec map_object_value(boolean()) -> map_phase_spec()
%% @doc Produces a spec for a map phase that simply returns
%%      the values of the objects from the input to the phase.
%%      That is:
%%      riak_kv_mrc_pipe:mapred(BucketKeys, [map_object_value(true)]).
%%      Would return a list that contains the value of each
%%      object named by BucketKeys.
map_object_value(Acc) ->
    {map, {modfun, riak_kv_mapreduce, map_object_value}, none, Acc}.

%% @spec map_object_value(riak_object:riak_object(), term(), term()) -> [term()]
%% @doc map phase function for map_object_value/1
%%      If the RiakObject is the tuple {error, notfound}, the
%%      behavior of this function is defined by the Action argument.
%%      Values for Action are:
%%        `<<"filter_notfound">>' : produce no output (literally [])
%%        `<<"include_notfound">>' : produce the not-found as the result
%%                                   (literally [{error, notfound}])
%%        `<<"include_keydata">>' : produce the keydata as the result
%%                                  (literally [KD])
%%        `{struct,[{<<"sub">>,term()}]}' : produce term() as the result
%%                                          (literally term())
%%      The last form has a strange stucture, in order to allow
%%      its specification over the HTTP interface
%%      (as JSON like ..."arg":{"sub":1234}...).
map_object_value({error, notfound}=NF, KD, Action) ->
    notfound_map_action(NF, KD, Action);
map_object_value(RiakObject, _, _) ->
    [riak_object:get_value(RiakObject)].

%% @spec map_object_value_list(boolean) -> map_phase_spec()
%% @doc Produces a spec for a map phase that returns the values of
%%      the objects from the input to the phase.  The difference
%%      between this phase and that of map_object_value/1 is that
%%      this phase assumes that the value of the riak object is
%%      a list.  Thus, if the input objects to this phase have values
%%      of [a,b], [c,d], and [e,f], the output of this phase is
%%      [a,b,c,d,e,f].
map_object_value_list(Acc) ->
    {map, {modfun, riak_kv_mapreduce, map_object_value_list}, none, Acc}.

%% @spec map_object_value_list(riak_object:riak_object(), term(), term()) ->
%%                            [term()]
%% @doc map phase function for map_object_value_list/1
%%      See map_object_value/3 for a description of the behavior of
%%      this function with the RiakObject is {error, notfound}.
map_object_value_list({error, notfound}=NF, KD, Action) ->
    notfound_map_action(NF, KD, Action);
map_object_value_list(RiakObject, _, _) ->
    riak_object:get_value(RiakObject).

%% implementation of the notfound behavior for
%% map_object_value and map_object_value_list
notfound_map_action(_NF, _KD, <<"filter_notfound">>)    -> [];
notfound_map_action(NF, _KD, <<"include_notfound">>)    -> [NF];
notfound_map_action(_NF, KD, <<"include_keydata">>)     -> [KD]; 
notfound_map_action(_NF, _KD, {struct,[{<<"sub">>,V}]}) -> V.

%%
%% Reduce Phases
%%

%% @spec reduce_identity(boolean()) -> reduce_phase_spec()
%% @doc Produces a spec for a reduce phase that simply returns
%%      back [Bucket, Key] for each BKey it's handed.  
reduce_identity(Acc) ->
    {reduce, {modfun, riak_kv_mapreduce, reduce_identity}, none, Acc}.

%% @spec reduce_identity([term()], term()) -> [term()]
%% @doc map phase function for reduce_identity/1
reduce_identity(List, _) -> 
    F = fun({{Bucket, Key}, _}, Acc) ->
                %% Handle BKeys with extra data.
                [[Bucket, Key]|Acc];
           ({Bucket, Key}, Acc) ->
                %% Handle BKeys.
                [[Bucket, Key]|Acc];
           ([Bucket, Key], Acc) ->
                %% Handle re-reduces.
                [[Bucket, Key]|Acc];
           ([Bucket, Key, KeyData], Acc) ->
                [[Bucket, Key, KeyData]|Acc];
           (Other, _Acc) ->
                %% Fail loudly on anything unexpected.
                lager:error("Unhandled entry: ~p", [Other]),
                throw({unhandled_entry, Other})
        end,
    lists:foldl(F, [], List).


-spec reduce_index_identity(list(riak_kv_pipe_index:index_keydata()|
                                    list(riak_kv_pipe_index:index_keydata())),
                                any()) ->
                                    list(riak_kv_pipe_index:index_keydata()).
reduce_index_identity(List, _) ->
    F = fun({{Bucket, Key}, undefined}, Acc) ->
                [{Bucket, Key}|Acc];
            ({{Bucket, Key}, KeyData}, Acc) when is_list(KeyData) ->
                [{{Bucket, Key}, KeyData}|Acc];
            (PrevAcc, Acc) when is_list(PrevAcc) ->
                Acc ++ PrevAcc;
            ({Bucket, Key}, Acc) ->
                [{Bucket, Key}|Acc];
            (Other, Acc) ->
                lager:warning("Unhandled entry: ~p", [Other]),
                Acc
        end,
    lists:foldl(F, [], List).

-spec reduce_index_extractinteger(list(riak_kv_pipe_index:index_keydata()|
                                        list(riak_kv_pipe_index:index_keydata())),
                                    {atom(), atom(), keep(), 
                                        non_neg_integer(),
                                        pos_integer()}) ->
                                            list(riak_kv_pipe_index:index_keydata()).
reduce_index_extractinteger(List,
                            {InputTerm, OutputTerm, Keep, PreBytes, IntSize}) ->
    F =
    fun({{Bucket, Key}, KeyTermList}, Acc) when is_list(KeyTermList) ->
            case lists:keyfind(OutputTerm, 1, KeyTermList) of
                false ->
                    case lists:keyfind(InputTerm, 1, KeyTermList) of
                        {InputTerm, <<_P:PreBytes/binary,
                                        I:IntSize/integer,
                                        _T/binary>>} ->
                            KeyTermList0 =
                                case Keep of
                                    all ->
                                        [{OutputTerm, I}|KeyTermList];
                                    this ->
                                        [{OutputTerm, I}]
                                end,
                            [{{Bucket, Key}, KeyTermList0}|Acc];
                        _Other ->
                            Acc
                    end;
                _ ->
                    [{{Bucket, Key}, KeyTermList}|Acc]
            end;
        (PrevAcc, Acc) when is_list(PrevAcc), is_list(Acc) ->
            Acc ++ PrevAcc;
        (_Other, Acc) ->
            Acc
    end,
    lists:foldl(F, [], List).

-spec reduce_index_byrange(list(riak_kv_pipe_index:index_keydata()|
                                list(riak_kv_pipe_index:index_keydata())),
                            {atom(), keep(),
                                term(), term()}) ->
                                    list(riak_kv_pipe_index:index_keydata()).
reduce_index_byrange(List, {InputTerm, Keep, LowRange, HighRange}) ->
    F =
    fun({{Bucket, Key}, KeyTermList}, Acc) when is_list(KeyTermList) ->
            case lists:keyfind(InputTerm, 1, KeyTermList) of
                {InputTerm, ToTest} when ToTest >=LowRange, ToTest < HighRange ->
                    Output =
                        case Keep of
                            all ->
                                {{Bucket, Key}, KeyTermList};
                            this ->
                                {{Bucket, Key}, [{InputTerm, ToTest}]}
                        end,
                    [Output|Acc];
                _ ->
                    Acc
            end;
        (PrevAcc, Acc) when is_list(PrevAcc) ->
            Acc ++ PrevAcc;
        (_, Acc) ->
            Acc
    end,
    lists:foldl(F, [], List).
            
-spec reduce_index_regex(list(riak_kv_pipe_index:index_keydata()|
                                list(riak_kv_pipe_index:index_keydata())),
                            {atom(), keep(),
                                binary()}) ->
                                    list(riak_kv_pipe_index:index_keydata()).
reduce_index_regex(List, {InputTerm, Keep, CompiledRe}) ->
    F =
    fun({{Bucket, Key}, KeyTermList}, Acc) when is_list(KeyTermList) ->
            case lists:keyfind(InputTerm, 1, KeyTermList) of
                {InputTerm, ToTest} ->
                    case re:run(ToTest, CompiledRe) of
                        {match, _} ->
                            Output =
                                case Keep of
                                    all ->
                                        {{Bucket, Key}, KeyTermList};
                                    this ->
                                        {{Bucket, Key}, [{InputTerm, ToTest}]}
                                end,
                            [Output|Acc];
                        _ ->
                            Acc
                    end;
                false ->
                    Acc
            end;
        (PrevAcc, Acc) when is_list(PrevAcc) ->
            Acc ++ PrevAcc;
        (_, Acc) ->
            Acc
    end,
    lists:foldl(F, [], List).


-spec reduce_index_max(list(riak_kv_pipe_index:index_keydata()|
                                list(riak_kv_pipe_index:index_keydata())),
                            {atom(), keep()}) ->
                                list(riak_kv_pipe_index:index_keydata()).
reduce_index_max(List, {InputTerm, Keep}) ->
    F =
    fun({{Bucket, Key}, KeyTermList}, none) when is_list(KeyTermList) ->
            case lists:keyfind(InputTerm, 1, KeyTermList) of
                {InputTerm, ToTest} ->
                    case Keep of
                        all ->
                            {{Bucket, Key}, KeyTermList};
                        this ->
                            {{Bucket, Key}, [{InputTerm, ToTest}]}
                    end;
                false ->
                    none
            end;
        ({{Bucket, Key}, KeyTermList}, {{MaxBucket, MaxKey}, MaxKeyTermList})
                                            when is_list(KeyTermList) ->
            case lists:keyfind(InputTerm, 1, KeyTermList) of
                {InputTerm, ToTest} ->
                    case lists:keyfind(InputTerm, 1, MaxKeyTermList) of
                        {InputTerm, MaxTest} when ToTest > MaxTest ->
                            case Keep of
                                all ->
                                    {{Bucket, Key}, KeyTermList};
                                this ->
                                    {{Bucket, Key}, [{InputTerm, ToTest}]}
                            end;
                        _ ->
                            {{MaxBucket, MaxKey}, MaxKeyTermList}
                    end;
                _ ->
                    {{MaxBucket, MaxKey}, MaxKeyTermList}
            end
    end,
    case lists:foldl(F, none, lists:flatten(List)) of
        none ->
            [];
        R ->
            [R]
    end.


%% @spec reduce_set_union(boolean()) -> reduce_phase_spec()
%% @doc Produces a spec for a reduce phase that produces the
%%      union-set of its input.  That is, given an input of:
%%         [a,a,a,b,c,b]
%%      this phase will output
%%         [a,b,c]
reduce_set_union(Acc) ->
    {reduce, {modfun, riak_kv_mapreduce, reduce_set_union}, none, Acc}.

%% @spec reduce_set_union([term()], term()) -> [term()]
%% @doc reduce phase function for reduce_set_union/1
reduce_set_union(List, _) ->
    sets:to_list(sets:from_list(List)).

%% @spec reduce_sum(boolean()) -> reduce_phase_spec()
%% @doc Produces a spec for a reduce phase that produces the
%%      sum of its inputs.  That is, given an input of:
%%         [1,2,3]
%%      this phase will output
%%         [6]
reduce_sum(Acc) ->
    {reduce, {modfun, riak_kv_mapreduce, reduce_sum}, none, Acc}.

%% @spec reduce_sum([number()], term()) -> [number()]
%% @doc reduce phase function for reduce_sum/1
reduce_sum(List, _) ->
    [lists:foldl(fun erlang:'+'/2, 0, not_found_filter(List))].

%% @spec reduce_plist_sum(boolean()) -> reduce_phase_spec()
%% @doc Produces a spec for a reduce phase that expects a proplist or
%%      a list of proplists.  where all values are numbers, and
%%      produces a proplist where all values are the sums of the
%%      values of each property from input proplists.
reduce_plist_sum(Acc) ->
    {reduce, {modfun, riak_kv_mapreduce, reduce_plist_sum}, none, Acc}.

%% @spec reduce_plist_sum([{term(),number()}|[{term(),number()}]], term())
%%       -> [{term(), number()}]
%% @doc reduce phase function for reduce_plist_sum/1
reduce_plist_sum([], _) -> [];
reduce_plist_sum(PList, _) ->
    dict:to_list(
      lists:foldl(
        fun({K,V},Dict) ->
                dict:update(K, fun(DV) -> V+DV end, V, Dict)
        end,
        dict:new(),
        if is_tuple(hd(PList)) -> PList;
           true -> lists:flatten(PList)
        end)).

%% @spec reduce_sort(boolean()) -> reduce_phase_spec()
%% @doc Produces a spec for a reduce phase that sorts its
%%      inputs in ascending order using lists:sort/1.
reduce_sort(Acc) ->
    {reduce, {modfun, riak_kv_mapreduce, reduce_sort}, none, Acc}.

%% @spec reduce_sort([term()], term()) -> [term()]
%% @doc reduce phase function for reduce_sort/1
reduce_sort(List, _) ->
    lists:sort(List).


%% @spec reduce_count_inputs(boolean()) -> reduce_phase_spec()
%% @doc Produces a spec for a reduce phase that counts its
%%      inputs.  Inputs to this phase must not be integers, or
%%      they will confuse the counting.  The output of this
%%      phase is a list of one integer.
%%
%%      The original purpose of this function was to count
%%      the results of a key-listing.  For example:
%%```
%%      [KeyCount] = riak_kv_mrc_pipe:mapred(<<"my_bucket">>,
%%                      [riak_kv_mapreduce:reduce_count_inputs(true)]).
%%'''
%%      KeyCount will contain the number of keys found in "my_bucket".
reduce_count_inputs(Acc) ->
    {reduce, {modfun, riak_kv_mapreduce, reduce_count_inputs}, none, Acc}.

%% @spec reduce_count_inputs([term()|integer()], term()) -> [integer()]
%% @doc reduce phase function for reduce_count_inputs/1
reduce_count_inputs(Results, _) ->
    [ lists:foldl(fun input_counter_fold/2, 0, Results) ].

%% @spec input_counter_fold(term()|integer(), integer()) -> integer()
input_counter_fold(PrevCount, Acc) when is_integer(PrevCount) ->
    PrevCount+Acc;
input_counter_fold(_, Acc) ->
    1+Acc.


%% @spec reduce_string_to_integer(boolean()) -> reduce_phase_spec()
%% @doc Produces a spec for a reduce phase that converts
%%      its inputs to integers. Inputs can be either Erlang
%%      strings or binaries.
reduce_string_to_integer(Acc) ->
    {reduce, {modfun, riak_kv_mapreduce, reduce_string_to_integer}, none, Acc}.

%% @spec reduce_string_to_integer([number()], term()) -> [number()]
%% @doc reduce phase function for reduce_sort/1
reduce_string_to_integer(List, _) ->
    [value_to_integer(I) || I <- not_found_filter(List)].

value_to_integer(V) when is_list(V) ->
    list_to_integer(V);
value_to_integer(V) when is_binary(V) ->
    value_to_integer(binary_to_list(V));
value_to_integer(V) when is_integer(V) ->
    V.

%% Helper functions
not_found_filter(Values) ->
    [Value || Value <- Values,
              is_datum(Value)].
is_datum({not_found, _}) ->
    false;
is_datum({not_found, _, _}) ->
    false;
is_datum(_) ->
    true.

%% unit tests %%
map_identity_test() ->
    O1 = riak_object:new(<<"a">>, <<"1">>, "value1"),
    [O1] = map_identity(O1, test, test).

map_object_value_test() ->
    O1 = riak_object:new(<<"a">>, <<"1">>, "value1"),
    O2 = riak_object:new(<<"a">>, <<"1">>, ["value1"]),
    ["value1"] = map_object_value(O1, test, test),
    ["value1"] = map_object_value_list(O2, test, test),
    [] = map_object_value({error, notfound}, test, <<"filter_notfound">>),
    [{error,notfound}] = map_object_value({error, notfound}, test, <<"include_notfound">>).

reduce_set_union_test() ->
    [bar,baz,foo] = lists:sort(reduce_set_union([foo,foo,bar,baz], test)).

reduce_sum_test() ->
    [10] = reduce_sum([1,2,3,4], test).

reduce_plist_sum_test() ->
    PLs = [[{a, 1}], [{a, 2}],
           [{b, 1}], [{b, 4}]],
    [{a,3},{b,5}] = reduce_plist_sum(PLs, test),
    [{a,3},{b,5}] = reduce_plist_sum(lists:flatten(PLs), test),
    [] = reduce_plist_sum([], test).

map_spec_form_test_() ->
    lists:append(
      [ [?_assertMatch({map, {modfun, riak_kv_mapreduce, F}, _, true},
                       riak_kv_mapreduce:F(true)),
         ?_assertMatch({map, {modfun, riak_kv_mapreduce, F}, _, false},
                       riak_kv_mapreduce:F(false))]
        || F <- [map_identity, map_object_value, map_object_value_list] ]).

reduce_spec_form_test_() ->
    lists:append(
      [ [?_assertMatch({reduce, {modfun, riak_kv_mapreduce, F}, _, true},
                       riak_kv_mapreduce:F(true)),
         ?_assertMatch({reduce, {modfun, riak_kv_mapreduce, F}, _, false},
                       riak_kv_mapreduce:F(false))]
        || F <- [reduce_set_union, reduce_sum, reduce_plist_sum] ]).

reduce_sort_test() ->
    [a,b,c] = reduce_sort([b,a,c], none),
    [1,2,3,4,5] = reduce_sort([4,2,1,3,5], none),
    ["a", "b", "c"] = reduce_sort(["c", "b", "a"], none),
    [<<"a">>, <<"is">>, <<"test">>, <<"this">>] = reduce_sort([<<"this">>, <<"is">>, <<"a">>, <<"test">>], none).

reduce_string_to_integer_test() ->
    [1,2,3] = reduce_string_to_integer(["1", "2", "3"], none),
    [1,2,3] = reduce_string_to_integer([<<"1">>, <<"2">>, <<"3">>], none),
    [1,2,3,4,5] = reduce_string_to_integer(["1", <<"2">>, <<"3">>, "4", "5"], none),
    [1,2,3,4,5] = reduce_string_to_integer(["1", <<"2">>, <<"3">>, 4, 5], none).

reduce_count_inputs_test() ->
    ?assertEqual([1], reduce_count_inputs([{"b1","k1"}], none)),
    ?assertEqual([2], reduce_count_inputs([{"b1","k1"},{"b2","k2"}],
                                          none)),
    ?assertEqual([9], reduce_count_inputs(
                        [{"b1","k1"},{"b2","k2"},{"b3","k3"}]
                        ++ reduce_count_inputs([{"b4","k4"},{"b5","k5"}],
                                               none)
                        ++ reduce_count_inputs(
                             [{"b4","k4"},{"b5","k5"},
                              {"b5","k5"},{"b5","k5"}],
                             none),
                        none)).

reduce_index_identity_test() ->
    A = {{<<"B1">>, <<"K1">>}, [{term, <<"KD1">>}]},
    B = {{<<"B2">>, <<"K2">>}, [{term, <<"KD2">>}]},
    C = {{<<"B3">>, <<"K3">>}, [{term, <<"KD3">>}, {extract, 4}]},
    D = {{<<"B4">>, <<"K4">>}, undefined},
    E = {<<"B5">>, <<"K5">>},
    F = {{<<"B6">>, <<"K6">>}, undefined},
    G = {{<<"B7">>, <<"K7">>}, undefined},
    H = {{<<"B8">>, <<"K8">>}, undefined},
    R0 = commassidem_check(fun reduce_index_identity/2, undefined, A, B, C, D),
    R1 = commassidem_check(fun reduce_index_identity/2, undefined, A, B, C, E),
    R2 = commassidem_check(fun reduce_index_identity/2, undefined, D, F, G, H),
    D0 = element(1, D),
    ?assertMatch([A, B, C, D0], R0),
    ?assertMatch([A, B, C, E], R1),
    ?assertMatch([{<<"B4">>, <<"K4">>},
                    {<<"B6">>, <<"K6">>},
                    {<<"B7">>, <<"K7">>},
                    {<<"B8">>, <<"K8">>}], R2).

reduce_index_extractinteger_test() ->
    A = {{<<"B1">>, <<"K1">>}, [{term, <<0:8/integer, 1:32/integer, 0:8/integer>>}]},
    B = {{<<"B2">>, <<"K2">>}, [{term, <<0:8/integer, 2:32/integer>>}, {extract, 26}]},
    C = {{<<"B3">>, <<"K3">>}, [{extract, 99}, {term, <<0:8/integer, 3:32/integer, 0:16/integer>>}]},
    D = {{<<"B4">>, <<"K4">>}, undefined},
    E = {{<<"EB5">>, <<"EK5">>}, <<0:4/integer>>},
    R0 = commassidem_check(fun reduce_index_extractinteger/2, {term, extint, all, 1, 32}, A, B, C, D),
    R1 = commassidem_check(fun reduce_index_extractinteger/2, {term, extint, this, 1, 32}, A, B, C, E),
    ExpR0 = 
        [{{<<"B1">>, <<"K1">>}, [{extint, 1}, {term, <<0:8/integer, 1:32/integer, 0:8/integer>>}]},
        {{<<"B2">>, <<"K2">>}, [{extint, 2}, {term, <<0:8/integer, 2:32/integer>>}, {extract, 26}]},
        {{<<"B3">>, <<"K3">>}, [{extint, 3}, {extract, 99}, {term, <<0:8/integer, 3:32/integer, 0:16/integer>>}]}
        ],
    ExpR1 =
        [{{<<"B1">>, <<"K1">>}, [{extint, 1}]},
        {{<<"B2">>, <<"K2">>}, [{extint, 2}]},
        {{<<"B3">>, <<"K3">>}, [{extint, 3}]}
        ],
    ?assertMatch(ExpR0, R0),
    ?assertMatch(ExpR1, R1).

reduce_index_byrange_test() ->
    A = {{<<"B1">>, <<"K1">>}, [{extint, 1}]},
    B = {{<<"B2">>, <<"K2">>}, [{extint, 2}]},
    C = {{<<"B3">>, <<"K3">>}, [{extint, 3}]},
    D = {{<<"B4">>, <<"K4">>}, [{extint, 4}]},
    E = {{<<"E5">>}},
    F = {{<<"F6">>, <<"F7">>}, undefined},
    R0 = commassidem_check(fun reduce_index_byrange/2, {extint, all, 2, 4}, A, B, C, D),
    commassidem_check(fun reduce_index_byrange/2, {extint, this, 2, 4}, A, B, C, E),
    commassidem_check(fun reduce_index_byrange/2, {extint, all, 2, 4}, A, B, C, F),
    ?assertMatch([B, C], R0).

reduce_index_regex_test() ->
    {ok, R} = re:compile(".*99.*"),
    A = {{<<"B1">>, <<"K1">>}, [{term, <<"v99a">>}]},
    B = {{<<"B2">>, <<"K2">>}, [{term, <<"v99b">>}]},
    C = {{<<"B3">>, <<"K3">>}, [{term, <<"v98a">>}]},
    D = {{<<"B4">>, <<"K4">>}, [{term, <<"v99d">>}]},
    E = {{<<"E5">>}},
    F = {{<<"F6">>, <<"F7">>}, undefined},
    R0 = commassidem_check(fun reduce_index_regex/2, {term, this, R}, A, B, C, D),
    commassidem_check(fun reduce_index_regex/2, {term, this, R}, A, B, C, E),
    commassidem_check(fun reduce_index_regex/2, {term, all, R}, A, B, C, F),
    ?assertMatch([A, B, D], R0).

reduce_index_max_test() ->
    A = {{<<"B1">>, <<"K1">>}, [{int, 5}]},
    B = {{<<"B2">>, <<"K2">>}, [{int, 7}, {term, <<"v7">>}]},
    C = {{<<"B3">>, <<"K3">>}, [{int, 8}]},
    D = {{<<"B4">>, <<"K4">>}, [{term, 9}]},
    R = commassidem_check(fun reduce_index_max/2, {int, this}, A, B, C, D),
    ?assertMatch([C], R).

commassidem_check(F, Args, A, B, C, D) ->
    % Is the reduce function commutative, associative and idempotent
    ID1 = F([A, B, C, D], Args),
    ID2 = F([A, D] ++ F([C, B], Args), Args),
    ID3 = F([F([A], Args), F([B], Args), F([C], Args), F([D], Args)], Args),
    R = lists:sort(ID1),
    ?assertMatch(R, lists:sort(ID2)),
    ?assertMatch(R, lists:sort(ID3)),
    R.