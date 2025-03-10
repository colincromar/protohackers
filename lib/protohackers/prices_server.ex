defmodule Protohackers.PricesServer do
  use GenServer

  require Logger

  defstruct [:listen_socket, :supervisor]

  alias Protohackers.DB

  ## Callbacks

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    port = Keyword.fetch!(opts, :port)
    {:ok, supervisor} = Task.Supervisor.start_link(max_children: 100)

    listen_options = [
      ifaddr: {0, 0, 0, 0},
      mode: :binary,
      active: false,
      reuseaddr: true,
      exit_on_close: false,
      backlog: 100
    ]

    case :gen_tcp.listen(port, listen_options) do
      {:ok, listen_socket} ->
        Logger.info("Started server on port #{port}")
        state = %__MODULE__{listen_socket: listen_socket, supervisor: supervisor}
        {:ok, state, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, socket} ->
        Task.Supervisor.start_child(state.supervisor, fn -> handle_connection(socket) end)
        {:noreply, state, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  ## Helpers

  defp handle_connection(socket) do
    case recv_requests(socket, DB.new()) do
      :ok -> :ok
      {:error, reason} -> Logger.error("Failed to receive data: #{inspect(reason)}")
    end

    :gen_tcp.shutdown(socket, :write)
    :gen_tcp.close(socket)
  end

  defp recv_requests(socket, db) do
    case :gen_tcp.recv(socket, 9, 10_000) do
      {:ok, data} ->
        Logger.info("Received raw data: #{inspect(data)}")

        case handle_request(data, db) do
          {nil, db} ->
            recv_requests(socket, db)

          {response, db} ->
            :gen_tcp.send(socket, response)
            recv_requests(socket, db)

          :error ->
            {:error, :invalid_request}
        end

      {:error, :closed} ->
        Logger.info("Client closed the connection.")

      {:error, :timeout} ->
        recv_requests(socket, db)

      {:error, reason} ->
        Logger.error("Failed to receive data: #{inspect(reason)}")
    end
  end

  defp handle_request(<<?I, timestamp::32-signed-big, price::32-signed-big>>, db) do
    {nil, DB.add(db, timestamp, price)}
  end

  defp handle_request(<<?Q, mintime::32-signed-big, maxtime::32-signed-big>>, db) do
    avg = DB.query(db, mintime, maxtime)
    {<<avg::32-signed-big>>, db}
  end

  defp handle_request(_other, _db) do
    :error
  end
end
