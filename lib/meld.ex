defmodule Meld do
  @moduledoc """
  Request coalescing is a technique for reducing load on a system that is handling a large number of identical requests.

  When multiple requests with the same key are received within a certain period of time, the requests are combined or "coalesced" into a single request, rather than being processed separately.

  For example, consider a system that receives a large number of requests to retrieve data from a database. If many of these requests are identical (i.e. requesting the same data), it can be inefficient to process them all separately.
  Instead, the system can use request coalescing to combine identical requests into a single request that retrieves the data once and returns the results to all callers.

  Requests in `Meld` are similar to `Task` with the distinction that the request result is dispatched to all callers for a given key,
  instead of just returning the result for the original call.

  `Meld` uses one `Registry` for key registrations and one `Registry` for dispatching. As with `Task` only the owner of the request is allowed to await the result.
  """
  @type start_option :: {:name, :atom}

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
  Executes the given mfa or function while coalescing requests by key.
  If multiple requests with the same key are sent before the original request returns, they will be coalesced into a single request.

  The request can be awaited on using `await/2`, which will unregister the current process from the key subscription.

  Requests that are not awaited can receive messages through the mailbox, as a request sets up a monitor you should handle the following messages:

  * `{ticket_ref, result}` - the reply message where `ticket_ref` is the ticket reference returned by the request.ticket and result is the request result
  * `{:DOWN, ref, :process, pid, reason}` - since all requests are monitored, you will also receive the :DOWN message delivered by Process.monitor/1. If you receive the :DOWN message without a a reply, it means the task crashed

  ## Parameters

  * `name` - The name of the registry module that will handle the requests.
  * `key` - A unique identifier for the request. Multiple requests with the same key will be coalesced into a single request.
  * `mfa_or_fun` - Either a module function specified as an MFA tuple or a zero-arity function that will be executed when the request is handled.
  * `opts` - An optional keyword list of additional options. The following options are recognized:
    - `link` - If the current process should be linked to request process

  ## Examples

    iex> _request = Meld.request(:meld, "my_key", fn -> "value" end)
  """
  @spec request(term(), key :: term(), mfa_or_fun :: term(), keyword()) :: term() | {:error}
  def request(name, key, mfa_or_fun, opts \\ [])
      when is_atom(name) and is_function(mfa_or_fun, 0)
      when is_atom(name) and tuple_size(mfa_or_fun) == 3 do
    ticket = make_ref()
    owner = self()
    :ok = subscribe(name, key, ticket)

    case Meld.Supervisor.start_request(name, key, mfa_or_fun, opts) do
      {:ok, request_pid} ->
        ref = Process.monitor(request_pid)

        if opts[:link] do
          Process.link(request_pid)
        end

        %Meld.Request{
          key: key,
          pid: request_pid,
          owner: owner,
          ticket: ticket,
          ref: ref,
          registry: name
        }

      {:ok, _pid, value} ->
        :ok = unsubscribe(name, key)

        send(owner, {ticket, value})

        %Meld.Request{
          key: key,
          owner: owner,
          ticket: ticket,
          registry: name
        }

      {:error, _reason} = err ->
        :ok = unsubscribe(name, key)
        err
    end
  end

  @doc """
  Awaits a request and returns the value.

  In case the request process dies, the caller process will exit with the same reason as the task.

  A timeout, in milliseconds or :infinity, can be given with a default value of 5000.
  If the timeout is exceeded, then the caller process will exit.
  If the request process is linked to the caller process which is the case when a request is started with `link: true`, then the request process will also exit.
  If the request process is trapping exits or not linked to the caller process, then it will continue to run.

  This function assumes the requests's monitor is still active or the monitor's :DOWN message is in the message queue.
  If it has been demonitored, or the message already received, this function will wait for the duration of the timeout awaiting the message.

  ## Immediate results

  A request that is coalesced can be immediately resolved, this is to prevent missing a value due to requests that have returned and dispatched the result to its subscribers
  but still being alive and occupying the key. In that case the a`{ref, value}` message is sent immediately to the owner.

  The effect of this is that for requests that are immediately resolved no monitor is spawned.

  ## Examples

      iex> request = Meld.request(:meld, "key", fn -> 1 + 1 end)
      iex> Meld.await(request)
      2
  """
  @spec await(Meld.Request.t(), timeout) :: term()
  def await(request, timeout \\ 5_000)

  def await(
        %Meld.Request{owner: owner, key: key, registry: name} = request,
        timeout
      ) do
    if owner != self() do
      raise ArgumentError,
            "Request #{inspect(request)} must be awaited from owner but was: #{inspect(self())}"
    end

    received = receive_request(request, timeout)
    :ok = unsubscribe(name, key)

    case received do
      {:exit, reason} ->
        exit(reason)

      value ->
        value
    end
  end

  defp receive_request(%Meld.Request{ref: ref, ticket: ticket} = request, timeout) do
    receive do
      {^ticket, reply} ->
        if ref do
          Process.demonitor(ref, [:flush])
        end

        reply

      {:DOWN, ^ref, _, _proc, reason} ->
        {:exit, {reason, {__MODULE__, :await, [request, timeout]}}}
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        {:exit, {:timeout, {__MODULE__, :await, [request, timeout]}}}
    end
  end

  @spec subscribe(name :: term(), key :: term(), ref :: reference(), keyword()) :: :ok
  def subscribe(name, key, ref, _opts \\ []) do
    {:ok, _} = Registry.register(name, key, ref)
    :ok
  end

  @spec unsubscribe(name :: term(), key :: term(), keyword()) :: :ok
  def unsubscribe(name, key, _opts \\ []) do
    :ok = Registry.unregister(name, key)
  end
end
