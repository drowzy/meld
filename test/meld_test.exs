defmodule MeldTest do
  use ExUnit.Case
  doctest Meld

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

    for _ <- 1..100 do
      spawn(fn ->
        case Meld.request(name, key, fun) do
          {:error, err} ->
            refute err

          ok ->
            ok
        end
      end)
    end

    assert_receive {:done, _}, 600
    refute_receive {:done, _}, 600
  end

  test "if no existing key should run by itself", %{name: name} do
    key = "test"
    parent = self()
    ref = make_ref()
    count = 1..5

    fun = fn ->
      send(parent, {:done, ref})
      ref
    end

    for i <- count do
      spawn(fn ->
        Meld.request(name, "#{key}#{i}", fun)
      end)
    end

    for _ <- count, do: assert_receive {:done, _}
  end
end
