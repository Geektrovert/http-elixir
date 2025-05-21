defmodule Server.Listener do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    IO.puts("Logs from your program will appear here!")
    {:ok, socket} = :gen_tcp.listen(4221, [:binary, active: false, reuseaddr: true])
    # Start accepting connections
    send(self(), :accept)
    {:ok, socket}
  end

  def handle_info(:accept, socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    spawn(fn -> Server.handle_client(client) end)
    send(self(), :accept)
    {:noreply, socket}
  end
end
