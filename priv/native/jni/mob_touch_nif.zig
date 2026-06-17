//! mob_touch_nif — Android touch tier-1 ZIG plugin NIF.
//!
//! The Kotlin side is the plugin-owned bridge class
//! `io.mob.touch.MobTouchBridge` (a Window.Callback proxy that observes
//! `dispatchTouchEvent` without consuming it). `touch_start` returns :ok and
//! installs the observer; each touch lands via the exported nativeDeliverTouch
//! thunk and is sent to the requesting pid.
//!
//! Build path: compiled via `addZigObject` from `-Dplugin_zig_nifs`, reaching
//! mob-core ERTS / JNI bindings through `@import("erts")` / `@import("jni")`.
//! `get_jenv` + `g_jvm` are mob-core exports linked into the same `.so`.
//!
//! Registration: the JVM calls
//! `Java_io_mob_touch_MobTouchBridge_nativeRegister(jenv, cls)` at startup
//! (MobPluginBootstrap.registerAll -> register()); that thunk caches the bridge
//! jclass + the 2 method IDs. The numeric bridge args are all `long` so there is
//! no int/long varargs mixing.
const std = @import("std");
const erts = @import("erts");
const jni = @import("jni");

// mob-core exports (linked into the same .so). NOT duplicated.
extern fn get_jenv(attached: *c_int) ?*jni.JNIEnv;
extern var g_jvm: ?*jni.JavaVM;

// ── Plugin-owned bridge-class method-id cache ────────────────────────────
const TouchMethods = struct {
    start: jni.JMethodID = null,
    stop: jni.JMethodID = null,
};

var g_touch: TouchMethods = .{};
var g_touch_cls: jni.JClass = null;

// ── nativeRegister thunk — cache the bridge jclass + method ids ───────────
export fn Java_io_mob_touch_MobTouchBridge_nativeRegister(jenv: *jni.JNIEnv, cls: jni.JClass) callconv(.c) void {
    g_touch_cls = jni.newGlobalRef(jenv, cls);
    if (g_touch_cls == null) return;
    g_touch.start = jni.getStaticMethodID(jenv, cls, "touch_start", "(JJ)V");
    g_touch.stop = jni.getStaticMethodID(jenv, cls, "touch_stop", "()V");
}

// ── Thread-attach + pid round-trip helpers (mirror mob-core / video) ──────
inline fn detachIfAttached(attached: c_int) void {
    if (attached != 0) {
        if (g_jvm) |jvm| jni.detachCurrentThread(jvm);
    }
}

inline fn pidToJlong(pid: erts.ErlNifPid) jni.JLong {
    if (@sizeOf(erts.ERL_NIF_TERM) == @sizeOf(jni.JLong)) {
        return @bitCast(pid.pid);
    }
    return @intCast(pid.pid);
}

inline fn pidFromLong(jpid: jni.JLong) erts.ErlNifPid {
    if (@sizeOf(erts.ERL_NIF_TERM) == @sizeOf(jni.JLong)) {
        return .{ .pid = @bitCast(jpid) };
    }
    const low: u32 = @truncate(@as(u64, @bitCast(jpid)));
    return .{ .pid = low };
}

// ── Inbound delivery — the Window.Callback observer calls this ────────────
// Builds {:touch, %{phase, x, y, pointer, timestamp}}.
// phase: 0 down, 1 move, 2 up, 3 cancel.
export fn Java_io_mob_touch_MobTouchBridge_nativeDeliverTouch(
    jenv: *jni.JNIEnv,
    cls: jni.JClass,
    pid_long: jni.JLong,
    phase: c_int,
    x: f64,
    y: f64,
    pointer: c_int,
    timestamp: jni.JLong,
) callconv(.c) void {
    _ = jenv;
    _ = cls;
    var pid = pidFromLong(pid_long);
    const env = erts.enif_alloc_env() orelse return;
    defer erts.enif_free_env(env);
    const phase_atom = switch (phase) {
        0 => erts.atom(env, "down"),
        1 => erts.atom(env, "move"),
        2 => erts.atom(env, "up"),
        else => erts.atom(env, "cancel"),
    };
    const keys = [_]erts.ERL_NIF_TERM{
        erts.atom(env, "phase"),
        erts.atom(env, "x"),
        erts.atom(env, "y"),
        erts.atom(env, "pointer"),
        erts.atom(env, "timestamp"),
    };
    const vals = [_]erts.ERL_NIF_TERM{
        phase_atom,
        erts.enif_make_double(env, x),
        erts.enif_make_double(env, y),
        erts.enif_make_int(env, pointer),
        erts.enif_make_int64(env, timestamp),
    };
    const map = erts.makeMap(env, &keys, &vals) orelse return;
    const msg = erts.makeTuple(env, .{ erts.atom(env, "touch"), map });
    _ = erts.enif_send(null, &pid, env, msg);
}

// ── NIFs ──────────────────────────────────────────────────────────────────
fn nif_touch_start(env: ?*erts.ErlNifEnv, argc: c_int, argv: [*]const erts.ERL_NIF_TERM) callconv(.c) erts.ERL_NIF_TERM {
    _ = argc;
    var throttle: c_int = 16;
    _ = erts.enif_get_int(env, argv[0], &throttle);
    var pid: erts.ErlNifPid = undefined;
    _ = erts.enif_self(env, &pid);
    var attached: c_int = 0;
    const jenv = get_jenv(&attached) orelse return erts.atom(env, "error");
    jenv.*.CallStaticVoidMethod.?(jenv, g_touch_cls, g_touch.start, pidToJlong(pid), @as(jni.JLong, @intCast(throttle)));
    detachIfAttached(attached);
    return erts.ok(env);
}

fn nif_touch_stop(env: ?*erts.ErlNifEnv, argc: c_int, argv: [*]const erts.ERL_NIF_TERM) callconv(.c) erts.ERL_NIF_TERM {
    _ = argc;
    _ = argv;
    var attached: c_int = 0;
    const jenv = get_jenv(&attached) orelse return erts.atom(env, "error");
    jenv.*.CallStaticVoidMethod.?(jenv, g_touch_cls, g_touch.stop);
    detachIfAttached(attached);
    return erts.ok(env);
}

// ── NIF table + init entry point ─────────────────────────────────────────
fn nifLoad(env: ?*erts.ErlNifEnv, priv: *?*anyopaque, info: erts.ERL_NIF_TERM) callconv(.c) c_int {
    _ = env;
    _ = priv;
    _ = info;
    return 0;
}

const nif_funcs = [_]erts.ErlNifFunc{
    .{ .name = "touch_start", .arity = 1, .fptr = nif_touch_start, .flags = 0 },
    .{ .name = "touch_stop", .arity = 0, .fptr = nif_touch_stop, .flags = 0 },
};

var nif_entry: erts.ErlNifEntry = .{
    .major = erts.ERL_NIF_MAJOR_VERSION,
    .minor = erts.ERL_NIF_MINOR_VERSION,
    .name = "mob_touch_nif",
    .num_of_funcs = nif_funcs.len,
    .funcs = &nif_funcs,
    .load = nifLoad,
    .reload = null,
    .upgrade = null,
    .unload = null,
    .vm_variant = erts.ERL_NIF_VM_VARIANT,
    .options = 1,
    .sizeof_ErlNifResourceTypeInit = erts.SIZEOF_ErlNifResourceTypeInit,
    .min_erts = erts.ERL_NIF_MIN_ERTS_VERSION,
};

pub export fn mob_touch_nif_nif_init() callconv(.c) *erts.ErlNifEntry {
    return &nif_entry;
}
