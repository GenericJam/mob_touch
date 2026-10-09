defmodule MobTouchTest do
  use ExUnit.Case, async: true

  alias Mob.Plugin.SelfTest, as: Contract
  alias MobDev.Plugin.{Manifest, Validator}
  alias MobTouch.SelfTest

  @plugin_dir Path.expand("..", __DIR__)

  describe "plugin manifest" do
    setup do
      {:ok, manifest} = Manifest.load(@plugin_dir)
      %{manifest: manifest}
    end

    test "loads and validates clean (round-trips)", %{manifest: m} do
      assert {:ok, ^m} = Manifest.validate(m)
    end

    test "classifies as tier 3 (NIF + a demo screen)", %{manifest: m} do
      assert Manifest.tier(m) == 3
    end

    test "passes the full pre-publish validator (paths, NIF modules, permissions)",
         %{manifest: m} do
      assert %{errors: []} = Validator.validate_plugin(m, @plugin_dir)
    end

    test "declares the cross-platform NIF pattern: one module, both platforms",
         %{manifest: m} do
      assert [ios, android] = m.nifs
      assert ios.module == :mob_touch_nif and ios.platform == :ios and ios.lang == :objc
      assert android.module == :mob_touch_nif and android.platform == :android
      assert android.lang == :zig
    end

    test "registers no runtime permission capability (observing own touches needs none)",
         %{manifest: m} do
      assert m.permissions == []
    end

    test "every native source dir + Kotlin bridge the manifest references exists",
         %{manifest: m} do
      for %{native_dir: dir} <- m.nifs do
        assert File.dir?(Path.join(@plugin_dir, dir)), "missing #{dir}"
      end

      assert File.exists?(Path.join(@plugin_dir, m.android.bridge_kt))
    end

    test "declares the self-test, which passes the validator without a warning", %{manifest: m} do
      assert m.selftest == MobTouch.SelfTest
      assert %{errors: [], warnings: warnings} = Validator.validate_plugin(m, @plugin_dir)
      refute Enum.any?(warnings, &(&1 =~ "selftest"))
    end
  end

  describe "MobTouch.SelfTest" do
    test "on a host with no native library linked it fails, naming the NIF, instead of raising" do
      for platform <- [:ios, :android] do
        result = SelfTest.run(%{platform: platform, device: :simulator})
        assert {:fail, reason} = result
        assert reason =~ "mob_touch_nif is not linked"
        assert reason =~ "nif_not_loaded"
        assert Contract.result?(result)
      end
    end

    test "an unregistered Kotlin bridge or an unexpected NIF answer fails" do
      result = SelfTest.classify_nif("touch_start/1", {:error, :bridge_not_registered})
      assert {:fail, "touch_start/1: Kotlin MobTouchBridge not registered" <> _} = result
      assert Contract.result?(result)

      result = SelfTest.classify_nif("touch_stop/0", :error)
      assert result == {:fail, "touch_stop/0 returned :error, expected :ok"}
      assert Contract.result?(result)
    end

    test "a dispatched touch counts as injected even when no view consumed it" do
      assert SelfTest.accepted?(:ok)
      assert SelfTest.accepted?({:error, :dispatch_failed})
      refute SelfTest.accepted?({:error, :not_loaded})
      refute SelfTest.accepted?({:error, :not_supported})
    end

    test "a host that cannot inject is a skip that says what the injection returned" do
      result = SelfTest.injection_skip({:error, :not_loaded})
      assert {:skip, reason} = result
      assert reason =~ "{:error, :not_loaded}"
      assert Contract.result?(result)
    end

    test "the injected down and up observed at the injected dp coordinates pass" do
      send(self(), {:touch, %{phase: :down, x: 8.0, y: 8.4, pointer: 0, timestamp: 1}})
      send(self(), {:touch, %{phase: :move, x: 30.0, y: 30.0, pointer: 0, timestamp: 2}})
      send(self(), {:touch, %{phase: :up, x: 8.0, y: 8.0, pointer: 0, timestamp: 3}})
      assert SelfTest.await_touches(0) == :pass
    end

    test "a down without its up, or no touch at all, fails naming the missing phases" do
      send(self(), {:touch, %{phase: :down, x: 8.0, y: 8.0, pointer: 0, timestamp: 1}})
      result = SelfTest.await_touches(0)
      assert {:fail, reason} = result
      assert reason =~ "delivered no :up within 0 ms"
      assert Contract.result?(result)

      assert {:fail, reason} = SelfTest.await_touches(0)
      assert reason =~ "delivered no :down / :up"
    end

    test "coordinates in pixels instead of dp fail" do
      send(self(), {:touch, %{phase: :down, x: 22.0, y: 22.0, pointer: 0, timestamp: 1}})
      result = SelfTest.await_touches(0)
      assert {:fail, reason} = result
      assert reason =~ "not converting pixels to dp"
      assert Contract.result?(result)
    end

    test "a message outside the touch contract fails" do
      send(self(), {:touch, :garbage})
      result = SelfTest.await_touches(0)
      assert {:fail, "observer delivered :garbage" <> _} = result
      assert Contract.result?(result)
    end
  end

  describe "NIF stub agreement" do
    # Guards the .erl stub / manifest, not app code — VacuousTest can't see that.
    # credo:disable-for-next-line Jump.CredoChecks.VacuousTest
    test "the manifest NIF module is the shipped .erl stub and loads on the host" do
      assert Code.ensure_loaded?(:mob_touch_nif)
    end

    # Guards the .erl stub / manifest, not app code — VacuousTest can't see that.
    # credo:disable-for-next-line Jump.CredoChecks.VacuousTest
    test "every NIF the public API calls is exported by the stub at the right arity" do
      exports = :mob_touch_nif.module_info(:exports)

      for fa <- [touch_start: 1, touch_stop: 0] do
        assert fa in exports, "#{inspect(fa)} missing from mob_touch_nif exports"
      end
    end

    # Guards the .erl stub / manifest, not app code — VacuousTest can't see that.
    # credo:disable-for-next-line Jump.CredoChecks.VacuousTest
    test "host (no native linked) falls back to nif_not_loaded, not a load crash" do
      assert_raise ErlangError, ~r/nif_not_loaded/, fn ->
        :mob_touch_nif.touch_stop()
      end
    end
  end

  describe "public API surface" do
    test "exports the documented operations" do
      exports = MobTouch.__info__(:functions)

      for fa <- [start: 2, stop: 1] do
        assert fa in exports, "#{inspect(fa)} missing from MobTouch"
      end
    end
  end
end
