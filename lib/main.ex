defmodule Server do
  use Application

  def start(_type, _args) do
    Supervisor.start_link([{Task, fn -> Server.listen() end}], strategy: :one_for_one)
  end

  def listen() do
    # You can use print statements as follows for debugging, they'll be visible when running tests.
    IO.puts("Logs from your program will appear here!")

    # Since the tester restarts your program quite often, setting SO_REUSEADDR
    # ensures that we don't run into 'Address already in use' errors
    {:ok, socket} = :gen_tcp.listen(4221, [:binary, active: false, reuseaddr: true])
    loop_accept(socket)
  end

  defp loop_accept(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    spawn(fn -> handle_client(client) end)
    loop_accept(socket)
  end

  def handle_client(client) do
    # Read the request
    {:ok, request} = :gen_tcp.recv(client, 0)

    # Process the request
    # get the request method and path
    [method, path | _] = String.split(request, " ")
    IO.puts("Method: #{method}")
    IO.puts("Path: #{path}")

    case method do
      "GET" ->
        case path do
          "/" ->
            :gen_tcp.send(client, "HTTP/1.1 200 OK\r\n\r\n")

          "/echo/" <> message ->
            :gen_tcp.send(client, success_with_content_data(message))

          "/user-agent" ->
            user_agent =
              request
              |> String.split("\r\n")
              |> Enum.find(fn line -> String.starts_with?(line, "User-Agent: ") end)
              |> case do
                nil -> ""
                line -> String.replace_prefix(line, "User-Agent: ", "")
              end

            :gen_tcp.send(client, success_with_content_data(user_agent))

          "/files" <> file_path ->
            directory = Application.get_env(:codecrafters_http_server, :directory, ".")
            # Clean up file_path (remove leading slash if present)
            file_path = String.trim_leading(file_path, "/")
            full_path = Path.join(directory, file_path)

            IO.puts("Reading file in path: #{full_path}")

            case File.read(full_path) do
              {:ok, contents} ->
                :gen_tcp.send(
                  client,
                  success_with_content_data(contents, "application/octet-stream")
                )

              {:error, _} ->
                :gen_tcp.send(client, "HTTP/1.1 404 Not Found\r\n\r\n")
            end

          _ ->
            :gen_tcp.send(client, "HTTP/1.1 404 Not Found\r\n\r\n")
        end

      _ ->
        :gen_tcp.send(client, "HTTP/1.1 405 Method Not Allowed\r\n\r\n")
    end

    # Close the socket
    :gen_tcp.close(client)
  end

  defp success_with_content_data(data, content_type \\ "text/plain") do
    "HTTP/1.1 200 OK\r\nContent-Type: #{content_type}\r\nContent-Length: #{byte_size(data)}\r\n\r\n#{data}"
  end
end

defmodule CLI do
  def main(args) do
    # Parse --directory flag
    {opts, _args, _invalid} = OptionParser.parse(args, switches: [directory: :string])
    directory = opts[:directory] || "."
    Application.put_env(:codecrafters_http_server, :directory, directory)

    # Start the Server application
    {:ok, _pid} = Application.ensure_all_started(:codecrafters_http_server)

    # Run forever
    Process.sleep(:infinity)
  end
end
