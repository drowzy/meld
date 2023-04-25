defmodule Meld.Supervisor do
  use Supervisor
  require Logger

  @spec start_link(atom(), keyword()) :: Supervisor.on_start()
  def start_link(name, opts \\ []) do
    sup_name = Module.concat([name, "Supervisor"])
    Supervisor.start_link(__MODULE__, {name, opts}, name: sup_name)
  end

  @impl true
  def init({name, _opts}) do
    children = [
      {DynamicSupervisor, name: Module.concat([name, "DynamicSupervisor"])},
      {Registry, keys: :unique, name: Module.concat([name, "Requests"])},
      {Registry, keys: :duplicate, name: name}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @spec start_request(name :: term(), mfa_or_fun :: term(), keyword()) ::
          {:ok, pid} | {:ok, pid, term()} | term()
  def start_request(name, key, mfa_or_fun, _opts \\ []) do
    sup_name = Module.concat([name, "DynamicSupervisor"])
    registry_name = Module.concat([name, "Requests"])

    child_spec = {Meld.Request.Worker, {key, mfa_or_fun, name, registry_name}}

    start_child(registry_name, sup_name, key, child_spec)
  end

  defp start_child(registry_name, sup_name, key, child_spec) do
    case Registry.lookup(registry_name, key) do
      [{pid, nil}] ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          start_child(registry_name, sup_name, key, child_spec)
        end

      [{pid, value}] ->
        {:ok, pid, value}

      [] ->
        case DynamicSupervisor.start_child(sup_name, child_spec) do
          {:ok, _pid} = ok ->
            ok

          {:error, {:already_started, pid}} ->
            if Process.alive?(pid) do
              {:ok, pid}
            else
              start_child(registry_name, sup_name, key, child_spec)
            end

          other ->
            other
        end
    end
  end
end
