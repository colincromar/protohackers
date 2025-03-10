defmodule Protohackers.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Protohackers.EchoServer, port: 4000},
      {Protohackers.PrimeServer, port: 5002},
      {Protohackers.PricesServer, port: 5003}
    ]

    opts = [strategy: :one_for_one, name: Protohackers.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
