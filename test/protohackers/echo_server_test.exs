defmodule Protohackers.EchoServerTest do
  use ExUnit.Case

  test "sets up socket" do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", 4000, mode: :binary, active: false)
    assert :gen_tcp.send(socket, "foo") == :ok
    assert :gen_tcp.send(socket, "bar") == :ok

    :gen_tcp.shutdown(socket, :write)
    assert :gen_tcp.recv(socket, 0, 4000) == {:ok, "foobar"}
  end

  test "has a max buffer size" do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", 4000, mode: :binary, active: false)

    assert :gen_tcp.send(socket, :binary.copy("a", 1024 * 100 + 1))
    assert :gen_tcp.recv(socket, 0) == {:error, :closed}
  end

  test "handles multiple concurrent connections" do
    tasks =
      for _ <- 1..4 do
        Task.async(fn ->
          {:ok, socket} = :gen_tcp.connect(~c"localhost", 4000, mode: :binary, active: false)
          assert :gen_tcp.send(socket, "foo") == :ok
          assert :gen_tcp.send(socket, "bar") == :ok

          :gen_tcp.shutdown(socket, :write)
          assert :gen_tcp.recv(socket, 0, 4000) == {:ok, "foobar"}
        end)
      end

    Enum.each(tasks, &Task.await/1)
  end
end
