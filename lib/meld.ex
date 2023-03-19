defmodule Meld do
  require Logger
  alias Meld.Error
  @type start_option :: {:name, :atom}

  @default_timeout 5_000

  @spec child_spec([start_option]) :: Supervisor.child_spec()
  def child_spec(options) do
    %{
      id: Keyword.get(options, :name, __MODULE__),
      start: {__MODULE__, :start_link, [options]},
      type: :supervisor
    }
  end

  @spec start_link([start_option]) :: Supervisor.on_start()
  def start_link(opts) do
    name =
      case Keyword.fetch(opts, :name) do
        {:ok, name} when is_atom(name) ->
          name

        {:ok, other} ->
          raise ArgumentError, "expected :name to be an atom, got: #{inspect(other)}"

        :error ->
          raise ArgumentError, "expected :name option to be present"
      end

    Meld.Supervisor.start_link(name, opts)
  end

  @doc """
  ## Examples
      Process.flag(:trap_exit, true)
      {:ok, _} = Meld.start_link(name: :meld)
       fun = fn ->
        Process.sleep(500)
        "value"
       end
       Meld.request(:meld, "key", fun)
  """
  @spec request(term(), key :: term(), mfa_or_fun :: term(), keyword()) :: term() | {:error}
  def request(name, key, mfa_or_fun, opts \\ [])
      when is_atom(name) and is_function(mfa_or_fun, 0)
      when is_atom(name) and tuple_size(mfa_or_fun) == 3 do
    timeout = opts[:timeout] || @default_timeout

    case Meld.Supervisor.start_request(name, key, mfa_or_fun, opts) do
      {:ok, owner} ->
        ref = make_ref()
        monitor_ref = Process.monitor(owner)

        :ok = Meld.Supervisor.register(name, key, ref)

        result =
          receive do
            {:DOWN, ^monitor_ref, :process, _pid, _} ->
              {:error, %Error{message: "process crashed"}}

            {^ref, %Error{} = err} ->
              {:error, err}

            {^ref, msg} ->
              msg
          after
            timeout ->
              {:error, :timeout}
          end

        true = Process.demonitor(monitor_ref, [:flush])
        :ok = Meld.Supervisor.unregister(name, key)
        result

      {:error, _reason} = err ->
        err
    end
  end
end
