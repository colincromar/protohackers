defmodule Protohackers.PrimeServer do
  use GenServer

  require Logger

  defstruct [:listen_socket, :supervisor]

  @spec start_link(keyword()) :: GenServer.on_start()
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
      packet: :line,
      exit_on_close: false,
      buffer: 1024 * 200
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
    recv_requests(socket)
    :gen_tcp.shutdown(socket, :write)
    :gen_tcp.close(socket)
  end

  defp recv_requests(socket) do
    case :gen_tcp.recv(socket, 0, 10_000) do
      {:ok, data} ->
        Logger.info("Received raw data: #{inspect(data)}")
        messages = String.split(data, "\n", trim: true)

        Enum.each(messages, fn message ->
          handle_request(socket, message)
        end)

        recv_requests(socket)

      {:error, :closed} ->
        Logger.info("Client closed the connection.")

      {:error, reason} ->
        Logger.error("Failed to receive data: #{inspect(reason)}")
        send_error_response(socket)
    end
  end

  defp handle_request(socket, data) do
    case Jason.decode(data) do
      {:ok, %{"method" => "isPrime", "number" => number}} when is_number(number) ->
        response = Jason.encode!(%{"method" => "isPrime", "prime" => prime?(number)}) <> "\n"
        Logger.info("Sending response: #{response}")
        :gen_tcp.send(socket, response)
        :ok

      _ ->
        error_response = Jason.encode!(%{"error" => "invalid request"}) <> "\n"
        Logger.info("Sending error response: #{error_response}")
        :gen_tcp.send(socket, error_response)
        {:error, :disconnect}
    end
  end

  defp send_error_response(socket, reason \\ "invalid request") do
    error_response = Jason.encode!(%{"error" => reason}) <> "\n"
    Logger.info("Sending error response: #{error_response}")
    :gen_tcp.send(socket, error_response)
  end

  defp prime?(number) when is_float(number), do: false
  defp prime?(number) when number <= 1, do: false
  defp prime?(number) when number in [2, 3], do: true

  defp prime?(number) do
    not Enum.any?(2..trunc(:math.sqrt(number)), &(rem(number, &1) == 0))
  end
end
