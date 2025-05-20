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

    #
    [header_section | body_parts] = String.split(request, "\r\n\r\n", parts: 2)
    headers = String.split(header_section, "\r\n")

    get_header = fn name ->
      headers
      |> Enum.find(fn line ->
        String.downcase(line) |> String.starts_with?(String.downcase(name) <> ":")
      end)
      |> case do
        nil -> nil
        line -> String.trim(String.split(line, ":", parts: 2) |> List.last())
      end
    end

    accept_encoding = get_header.("Accept-Encoding") || ""
    content_encoding = get_header.("Content-Encoding") || ""

    # Process the request
    # get the request method and path
    [method, path | _] = String.split(request, " ")
    IO.puts("Method: #{method}")
    IO.puts("Path: #{path}")

    case method do
      "GET" ->
        case path do
          "/" ->
            send_response(client, "200 OK", "", "text/plain")

          "/echo/" <> message ->
            {body, content_type, encoding} =
              compress_if_requested(message, "text/plain", accept_encoding)

            send_response(client, "200 OK", body, content_type, encoding)

          "/user-agent" ->
            user_agent =
              headers
              |> Enum.find(fn line -> String.starts_with?(line, "User-Agent: ") end)
              |> case do
                nil -> ""
                line -> String.replace_prefix(line, "User-Agent: ", "")
              end

            {body, content_type, encoding} =
              compress_if_requested(user_agent, "text/plain", accept_encoding)

            send_response(client, "200 OK", body, content_type, encoding)

          "/files" <> file_path ->
            directory = Application.get_env(:codecrafters_http_server, :directory, ".")
            # Clean up file_path (remove leading slash if present)
            file_path = String.trim_leading(file_path, "/")
            full_path = Path.join(directory, file_path)

            IO.puts("Reading file in path: #{full_path}")

            case File.read(full_path) do
              {:ok, contents} ->
                {body, content_type, encoding} =
                  compress_if_requested(contents, "application/octet-stream", accept_encoding)

                send_response(client, "200 OK", body, content_type, encoding)

              {:error, _} ->
                send_response(client, "404 Not Found", "", "text/plain")
            end

          _ ->
            send_response(client, "404 Not Found", "", "text/plain")
        end

      "POST" ->
        case path do
          "/files/" <> file_name ->
            directory = Application.get_env(:codecrafters_http_server, :directory, ".")
            full_path = Path.join(directory, file_name)

            body =
              case body_parts do
                [b] -> decompress_req(b, content_encoding)
                _ -> ""
              end

            case File.write(full_path, body) do
              :ok -> send_response(client, "201 Created", "", "text/plain")
              _ -> send_response(client, "500 Internal Server Error", "", "text/plain")
            end

          _ ->
            send_response(client, "404 Not Found", "", "text/plain")
        end

      _ ->
        send_response(client, "405 Method Not Allowed", "", "text/plain")
    end

    :gen_tcp.close(client)
  end

  defp compress_if_requested(data, content_type, accept_encoding) do
    if String.contains?(accept_encoding, "gzip") do
      compressed = :zlib.gzip(data)
      {compressed, content_type, "gzip"}
    else
      {data, content_type, nil}
    end
  end

  defp send_response(client, status, body, content_type, encoding \\ nil) do
    headers =
      [
        "HTTP/1.1 #{status}",
        "Content-Type: #{content_type}",
        "Content-Length: #{byte_size(body)}"
      ] ++ if encoding, do: ["Content-Encoding: #{encoding}"], else: []

    :gen_tcp.send(client, Enum.join(headers, "\r\n") <> "\r\n\r\n" <> body)
  end

  defp decompress_req(data, content_encoding) do
    if String.contains?(content_encoding, "gzip") do
      :zlib.gunzip(data)
    else
      data
    end
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
