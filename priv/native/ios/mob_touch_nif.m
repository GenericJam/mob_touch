/* mob_touch_nif — iOS touch tier-1 plugin NIF (Objective-C).
 *
 * Streams the user's raw touches WITHOUT consuming them: a passive
 * UIGestureRecognizer is added to the key window with cancelsTouchesInView=NO
 * and it never advances past .possible, so it observes every touch
 * (began/moved/ended/cancelled) while the touches still flow to the app's
 * views. Coordinates are window points (logical, == dp); moves are throttled.
 * Mirrors the Android Window.Callback observer and its {:touch, _} contract.
 *
 * Compiled as ObjC (-fobjc-arc) by the plugin C-NIF path (manifest lang:
 * :objc). Registered as the Erlang module mob_touch_nif via ERL_NIF_INIT.
 */
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <UIKit/UIKit.h>
#include <erl_nif.h>

enum { PHASE_DOWN = 0, PHASE_MOVE = 1, PHASE_UP = 2, PHASE_CANCEL = 3 };

static ErlNifPid g_pid;
static BOOL g_active = NO;
static double g_throttle_ms = 16;
static double g_last_move_ms = 0;
static int g_next_pointer = 0;
static NSMapTable *g_pointers = nil; // UITouch* (weak) -> NSNumber* id

static double now_ms(void) { return CACurrentMediaTime() * 1000.0; }

// ── {:touch, %{phase, x, y, pointer, timestamp}} delivery ──────────────────
static void send_touch(int phase, double x, double y, int pointer) {
  if (!g_active)
    return;
  ErlNifEnv *e = enif_alloc_env();
  const char *p = phase == PHASE_DOWN   ? "down"
                  : phase == PHASE_MOVE ? "move"
                  : phase == PHASE_UP   ? "up"
                                        : "cancel";
  ERL_NIF_TERM keys[5] = {enif_make_atom(e, "phase"), enif_make_atom(e, "x"),
                          enif_make_atom(e, "y"), enif_make_atom(e, "pointer"),
                          enif_make_atom(e, "timestamp")};
  ERL_NIF_TERM vals[5] = {enif_make_atom(e, p), enif_make_double(e, x),
                          enif_make_double(e, y), enif_make_int(e, pointer),
                          enif_make_int64(e, (long long)now_ms())};
  ERL_NIF_TERM map;
  enif_make_map_from_arrays(e, keys, vals, 5, &map);
  ERL_NIF_TERM msg = enif_make_tuple2(e, enif_make_atom(e, "touch"), map);
  ErlNifPid pid = g_pid;
  enif_send(NULL, &pid, e, msg);
  enif_free_env(e);
}

static int pointer_id(UITouch *t, BOOL assign) {
  NSNumber *existing = [g_pointers objectForKey:t];
  if (existing)
    return existing.intValue;
  if (!assign)
    return 0;
  int id = g_next_pointer++;
  [g_pointers setObject:@(id) forKey:t];
  return id;
}

// ── Passive observer recognizer (never recognizes; doesn't consume) ────────
@interface MobTouchObserver : UIGestureRecognizer
@end

@implementation MobTouchObserver
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  for (UITouch *t in touches) {
    CGPoint p = [t locationInView:self.view];
    send_touch(PHASE_DOWN, p.x, p.y, pointer_id(t, YES));
  }
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  double t_ms = now_ms();
  if (g_throttle_ms > 0 && t_ms - g_last_move_ms < g_throttle_ms)
    return;
  g_last_move_ms = t_ms;
  for (UITouch *t in touches) {
    CGPoint p = [t locationInView:self.view];
    send_touch(PHASE_MOVE, p.x, p.y, pointer_id(t, NO));
  }
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  for (UITouch *t in touches) {
    CGPoint p = [t locationInView:self.view];
    send_touch(PHASE_UP, p.x, p.y, pointer_id(t, NO));
    [g_pointers removeObjectForKey:t];
  }
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches
               withEvent:(UIEvent *)event {
  for (UITouch *t in touches) {
    CGPoint p = [t locationInView:self.view];
    send_touch(PHASE_CANCEL, p.x, p.y, pointer_id(t, NO));
    [g_pointers removeObjectForKey:t];
  }
}
@end

static MobTouchObserver *g_recognizer = nil;

static UIWindow *key_window(void) {
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if ([scene isKindOfClass:UIWindowScene.class]) {
      for (UIWindow *w in ((UIWindowScene *)scene).windows) {
        if (w.isKeyWindow)
          return w;
      }
    }
  }
  return UIApplication.sharedApplication.windows.firstObject;
}

// ── NIFs ────────────────────────────────────────────────────────────────────
static ERL_NIF_TERM nif_touch_start(ErlNifEnv *env, int argc,
                                    const ERL_NIF_TERM argv[]) {
  (void)argc;
  int throttle = 16;
  enif_get_int(env, argv[0], &throttle);
  enif_self(env, &g_pid);
  g_throttle_ms = throttle;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (g_recognizer)
      return; // already streaming
    UIWindow *win = key_window();
    if (!win)
      return;
    g_pointers = [NSMapTable weakToStrongObjectsMapTable];
    g_next_pointer = 0;
    MobTouchObserver *r = [[MobTouchObserver alloc] init];
    r.cancelsTouchesInView = NO;
    r.delaysTouchesBegan = NO;
    r.delaysTouchesEnded = NO;
    [win addGestureRecognizer:r];
    g_recognizer = r;
    g_active = YES;
  });
  return enif_make_atom(env, "ok");
}

static ERL_NIF_TERM nif_touch_stop(ErlNifEnv *env, int argc,
                                   const ERL_NIF_TERM argv[]) {
  (void)argc;
  (void)argv;
  g_active = NO;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (g_recognizer) {
      [g_recognizer.view removeGestureRecognizer:g_recognizer];
      g_recognizer = nil;
    }
    g_pointers = nil;
  });
  return enif_make_atom(env, "ok");
}

static ErlNifFunc nif_funcs[] = {
    {"touch_start", 1, nif_touch_start, 0},
    {"touch_stop", 0, nif_touch_stop, 0},
};

ERL_NIF_INIT(mob_touch_nif, nif_funcs, NULL, NULL, NULL, NULL)
