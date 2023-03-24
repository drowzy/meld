defmodule MeldTest do
  use ExUnit.Case, async: true

  setup do
    name = :test_meld
    _ = start_supervised!({Meld, name: :test_meld})

    {:ok, name: name}
  end

  test "should 'attach' to already existing request on key", %{name: name} do
    key = "test"
    parent = self()

    fun = fn ->
      ref = make_ref()

      Process.sleep(500)
      send(parent, {:done, ref})

      ref
    end

    requests =
      for _ <- 1..100 do
        spawn(fn ->
          request = Meld.request(name, key, fun)
          send(parent, {:request, request})
        end)

        receive do
          {:request, request} ->
            request
        after
          1_000 ->
            refute true
        end
      end

    assert started_procs_count(requests) == 1
    assert_receive {:done, _}, 600
    refute_receive {:done, _}, 600
  end

  test "delayed", %{name: name} do
    key = "delayed_test"
    fun = fn -> "value" end

    spawn(fn -> Meld.request(name, key, fun) end)

    Process.sleep(500)

    second = Meld.request(name, key, fun)

    assert "value" = Meld.await(second)
  end

  test "if no existing key should start a new process", %{name: name} do
    key = "test"
    parent = self()
    ref = make_ref()
    count = 1..5

    fun = fn ->
      send(parent, {:done, ref})
      ref
    end

    requests =
      for i <- count do
        Meld.request(name, "#{key}#{i}", fun)
      end

    assert started_procs_count(requests) == Enum.max(count)
    for _ <- count, do: assert_receive({:done, _})
  end

  test "receives message in mailbox when not awaited", %{name: name} do
    %{ticket: ticket, ref: ref} =
      Meld.request(name, "my_key", fn ->
        :done
      end)

    assert_receive {^ticket, :done}, 600
    assert_receive {:DOWN, ^ref, _, _, _}
  end

  test "caller should still be registred for the key when not awaiting request", %{name: name} do
    key = :crypto.strong_rand_bytes(10)
    caller = self()

    %{ticket: ticket, ref: ref} =
      Meld.request(name, key, fn ->
        :done
      end)

    assert_receive {^ticket, :done}, 600
    assert_receive {:DOWN, ^ref, _, _, _}
    assert [{^caller, _}] = Registry.lookup(name, key)
  end

  test "should receive a message when the value is immediately resolved", %{name: name} do
    registry = Module.concat([name, "Requests"])
    {:ok, _} = Registry.register(registry, "immediate_msg", "immediate")

    fun = fn -> "value" end
    %{ticket: ticket} = request = Meld.request(name, "immediate_msg", fun)
    assert request.pid == nil
    assert request.ref == nil

    assert_receive {^ticket, "immediate"}
  end

  test "can use any term as key", %{name: name} do
    keys = [
      {:my, :key},
      "my_key",
      %{my: :key},
      [:my, :key]
    ]

    for k <- keys do
      %Meld.Request{key: ^k} = req = Meld.request(name, k, fn -> "value" end)

      assert is_pid(req.pid)
    end
  end

  describe "await/2" do
    test "exits if there's a timeout", %{name: name} do
      request = %Meld.Request{owner: self(), ref: make_ref(), registry: name}
      assert {:timeout, {Meld, :await, [^request, 1]}} = catch_exit(Meld.await(request, 1))
    end

    test "exits if the process is down before receiving a message", %{name: name} do
      fun = fn ->
        Process.exit(self(), :normal)
        "value"
      end

      request = Meld.request(name, "proc_down", fun)

      assert {:noproc, {Meld, :await, [^request, 1]}} = catch_exit(Meld.await(request, 1))
    end

    test "can await request and get a value", %{name: name} do
      fun = fn -> "value" end

      request = Meld.request(name, "await_test", fun)
      assert "value" = Meld.await(request, 1)
    end

    test "can await a value that is immediately resolved", %{name: name} do
      registry = Module.concat([name, "Requests"])
      {:ok, _} = Registry.register(registry, "immediate", "immediate")
      fun = fn -> "value" end
      request = Meld.request(name, "immediate", fun)

      assert "immediate" == Meld.await(request, 1)
    end

    test "can await request with keys being any term", %{name: name} do
      keys = [
        {:my, :key},
        "my_key",
        %{my: :key},
        [:my, :key]
      ]

      for k <- keys do
        %Meld.Request{key: ^k} = req = Meld.request(name, k, fn -> "value" end)
        assert "value" = Meld.await(req)
      end
    end
  end

  defp started_procs_count(requests) do
    requests
    |> Enum.uniq_by(& &1.pid)
    |> length()
  end
end
