%% mob_touch_nif — Erlang NIF module for the touch tier-1 plugin.
%%
%% iOS: priv/native/ios/mob_touch_nif.m (Objective-C, a passive
%% UIGestureRecognizer on the key window). Android:
%% priv/native/jni/mob_touch_nif.zig (a Window.Callback observer via the
%% io.mob.touch.MobTouchBridge Kotlin bridge). Both register this module via
%% ERL_NIF_INIT and are statically linked into the host binary on device. On a
%% host dev build neither is linked, so on_load tolerates the failure and the
%% NIFs fall back to nif_error until the native merge links one.
%%
%% touch_start returns :ok and installs the observer; touches then arrive in the
%% caller's mailbox as {touch, Map} messages (see the MobTouch moduledoc).
-module(mob_touch_nif).
-export([touch_start/1, touch_stop/0]).
-on_load(init/0).

init() ->
    case erlang:load_nif("mob_touch_nif", 0) of
        ok -> ok;
        {error, _} -> ok
    end.

touch_start(_ThrottleMs) ->
    erlang:nif_error(nif_not_loaded).

touch_stop() ->
    erlang:nif_error(nif_not_loaded).
