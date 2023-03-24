defmodule Meld.Request do
  @type t :: %__MODULE__{}

  defstruct [
    :owner,
    :ticket,
    :ref,
    :key,
    :pid,
    :registry
  ]
end

defmodule Meld.Request.Worker do
  use GenServer
  require Logger
  alias Meld.Error

  @type t :: %__MODULE__{}
  defstruct [
    :dispatcher,
    :registry_name,
    :mfa_or_fun,
    :key
  ]

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      restart: :transient
    }
  end

  def start_link({key, _mfa_or_fun, _dispatcher, registry_name} = args) do
    GenServer.start_link(__MODULE__, args, name: {:via, Registry, {registry_name, key}})
  end

  @impl true
  def init({key, mfa_or_fun, dispatcher, registry_name}) do
    {:ok,
     %__MODULE__{
       dispatcher: dispatcher,
       registry_name: registry_name,
       key: key,
       mfa_or_fun: mfa_or_fun
     }, {:continue, :run}}
  end

  @impl true
  def handle_continue(
        :run,
        %__MODULE__{
          mfa_or_fun: fun,
          dispatcher: dispatcher,
          key: key,
          registry_name: registry_name
        } = state
      )
      when is_function(fun) do
    try do
      value = fun.()
      {_new, _old} = Registry.update_value(registry_name, key, fn _ -> value end)

      respond(dispatcher, key, value)
      {:stop, :normal, state}
    rescue
      e ->
        ex = %Error{
          message: Exception.message(e),
          stack: Process.info(self(), :current_stacktrace),
          key: key
        }

        :ok = respond(dispatcher, key, ex)

        {:stop, :shutdown, state}
    end
  end

  defp respond(dispatcher, key, value) do
    Registry.dispatch(dispatcher, key, fn entries ->
      for {pid, ref} <- entries do
        send(pid, {ref, value})
      end
    end)
  end
end
