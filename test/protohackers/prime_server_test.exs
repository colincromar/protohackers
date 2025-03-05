defmodule Protohackers.PrimeServerTest do
  use ExUnit.Case, async: true

  @timeout 6_000

  test "echoes back JSON" do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", 5002, mode: :binary, active: false)

    request_1 = Jason.encode!(%{method: "isPrime", number: 7}) <> "\n"
    request_2 = Jason.encode!(%{method: "isPrime", number: 6}) <> "\n"

    :gen_tcp.send(socket, request_1)

    case :gen_tcp.recv(socket, 0, @timeout) do
      {:ok, data} ->
        # Debugging
        IO.inspect(data, label: "Received Response 1")
        assert String.ends_with?(data, "\n")
        assert Jason.decode!(data) == %{"method" => "isPrime", "prime" => true}

      {:error, :closed} ->
        flunk("Connection closed before test could read first response")
    end

    :gen_tcp.send(socket, request_2)

    case :gen_tcp.recv(socket, 0, @timeout) do
      {:ok, data} ->
        # Debugging
        IO.inspect(data, label: "Received Response 2")
        assert String.ends_with?(data, "\n")
        assert Jason.decode!(data) == %{"method" => "isPrime", "prime" => false}

      {:error, :closed} ->
        flunk("Connection closed before test could read second response")
    end

    # Ensure graceful shutdown
    :gen_tcp.shutdown(socket, :write)
    assert :gen_tcp.recv(socket, 0, 1000) == {:error, :closed}
  end
end
