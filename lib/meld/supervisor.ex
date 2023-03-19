defmodule Meld.Supervisor do
  use Supervisor

  def start_link(name, opts \\ []) do
    Supervisor.start_link(__MODULE__, {name, opts}, name: Module.concat([name, "Supervisor"]))
  end

  def init({name, _opts}) do
    children = [
      {DynamicSupervisor, name: Module.concat([name, "DynamicSupervisor"])},
      {Registry, keys: :unique, name: Module.concat([name, "Registry"])},
      {Registry, keys: :duplicate, name: name}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @spec register(name :: term(), key :: term(), ref :: reference(), keyword()) :: :ok
  def register(name, key, ref, _opts \\ []) do
    {:ok, _} = Registry.register(name, key, ref)
    :ok
  end

  @spec unregister(name :: term(), key :: term(), keyword()) :: :ok
  def unregister(name, key, _opts \\ []) do
    :ok = Registry.unregister(name, key)
  end

  @spec start_request(name :: term(), mfa_or_fun :: term(), keyword()) :: {:ok, pid} | term()
  def start_request(name, key, mfa_or_fun, _opts \\ []) do
    sup_name = Module.concat([name, "DynamicSupervisor"])
    registry_name = Module.concat([name, "Registry"])
    request_name = {:via, Registry, {registry_name, key}}

    child_spec = {Meld.Request, {request_name, key, mfa_or_fun, name}}

    case DynamicSupervisor.start_child(sup_name, child_spec) do
      {:ok, _pid} = ok ->
        ok

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, _other} = err ->
        err
    end
  end
end
