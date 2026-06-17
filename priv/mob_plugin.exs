%{
  name: :mob_touch,
  mob_version: "~> 0.7",
  plugin_spec_version: 1,
  description: "Stream raw screen-touch coordinates (x/y) to a Mob screen",
  # A sample screen the host can navigate to by route. Pure-Elixir +
  # hot-pushable; drop it and this entry in a real app that builds its own UI.
  screens: [
    %{module: MobTouch.DemoScreen, default_route: "/mob_touch/demo"}
  ],
  nifs: [
    # iOS: Objective-C NIF, a passive UIGestureRecognizer on the key window.
    %{module: :mob_touch_nif, native_dir: "priv/native/ios", lang: :objc, platform: :ios},
    # Android: zig NIF bridging to the Window.Callback observer in the Kotlin
    # MobTouchBridge.
    %{module: :mob_touch_nif, native_dir: "priv/native/jni", lang: :zig, platform: :android}
  ],
  # No runtime permission: observing touches on the app's own window needs none.
  permissions: [],
  android: %{
    bridge_kt: "priv/native/android/MobTouchBridge.kt",
    # Implements MobActivityAware — it needs the Activity's Window to install
    # (and later restore) the touch observer.
    bridge_class: "io.mob.touch.MobTouchBridge"
  },
  ios: %{
    frameworks: ["UIKit"]
  }
}
