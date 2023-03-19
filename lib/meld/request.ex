defmodule Meld.Request do
  use GenServer
  require Logger
  alias Meld.Error

  @type t :: %__MODULE__{}
  defstruct [
    :dispatcher,
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

  def start_link({name, _key, _mfa_or_fun, _dispatcher} = args) do
    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init({_name, key, mfa_or_fun, dispatcher}) do
    {:ok,
     %__MODULE__{
       dispatcher: dispatcher,
       key: key,
       mfa_or_fun: mfa_or_fun
     }, {:continue, :run}}
  end

  @impl true
  def handle_continue(
        :run,
        %__MODULE__{mfa_or_fun: fun, dispatcher: dispatcher, key: key} = state
      )
      when is_function(fun) do
    try do
      value = fun.()
      :ok = respond(dispatcher, key, value)

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

  def respond(dispatcher, key, msg) do
    Registry.dispatch(dispatcher, key, fn entries ->
      for {pid, ref} <- entries do
        send(pid, {ref, msg})
      end
    end)
  end
end
