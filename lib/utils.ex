defmodule Utils do
  require Logger

  def compress_if_requested(data, content_type, accept_encoding) do
    if String.contains?(accept_encoding, "gzip") do
      compressed = :zlib.gzip(data)
      Logger.info("[compress] encoding=gzip content_type=#{content_type}")
      {compressed, content_type, "gzip"}
    else
      {data, content_type, nil}
    end
  end

  def decompress_req(data, content_encoding) do
    if String.contains?(content_encoding, "gzip") do
      Logger.info("[decompress] encoding=gzip")
      :zlib.gunzip(data)
    else
      data
    end
  end

  def send_response(
        client,
        status,
        body,
        content_type,
        encoding \\ nil,
        connection_close \\ false
      ) do
    headers =
      [
        "HTTP/1.1 #{status}",
        "Content-Type: #{content_type}",
        "Content-Length: #{byte_size(body)}"
      ] ++
        if(encoding, do: ["Content-Encoding: #{encoding}"], else: []) ++
        if connection_close, do: ["Connection: close"], else: []

    Logger.info(
      "[send_response] status=#{status} content_type=#{content_type} encoding=#{inspect(encoding)} length=#{byte_size(body)} connection_close=#{connection_close}"
    )

    :gen_tcp.send(client, Enum.join(headers, "\r\n") <> "\r\n\r\n" <> body)
  end

  def get_header(headers, name) do
    headers
    |> Enum.find(fn line ->
      String.downcase(line) |> String.starts_with?(String.downcase(name) <> ":")
    end)
    |> case do
      nil -> nil
      line -> String.trim(String.split(line, ":", parts: 2) |> List.last())
    end
  end

  # Parses a raw HTTP request from buffer. Returns {:ok, method, path, headers, body, rest} | :incomplete | :error
  def parse_request(buffer) do
    case String.split(buffer, "\r\n\r\n", parts: 2) do
      [header_section, rest] ->
        headers = String.split(header_section, "\r\n")
        [request_line | header_lines] = headers
        [method, path | _] = String.split(request_line, " ")

        content_length =
          header_lines
          |> Enum.find_value(0, fn line ->
            case String.downcase(line) do
              <<"content-length:", val::binary>> ->
                val |> String.trim() |> String.to_integer()

              _ ->
                nil
            end
          end)

        cond do
          content_length > 0 and byte_size(rest) < content_length ->
            Logger.info(
              "[parse_request] incomplete_request method=#{method} path=#{path} content_length=#{content_length} received=#{byte_size(rest)}"
            )

            :incomplete

          true ->
            body = if content_length > 0, do: String.slice(rest, 0, content_length), else: ""
            total_length = byte_size(header_section) + 4 + byte_size(body)
            leftover = String.slice(buffer, total_length, byte_size(buffer) - total_length)

            Logger.info(
              "[parse_request] parsed method=#{method} path=#{path} content_length=#{content_length} body_size=#{byte_size(body)} leftover_size=#{byte_size(leftover)}"
            )

            {:ok, method, path, [request_line | header_lines], body, leftover}
        end

      [_] ->
        Logger.info("[parse_request] incomplete_request waiting_for_more_data")
        :incomplete

      _ ->
        Logger.info("[parse_request] malformed_request parse_error")
        :error
    end
  end

  def connection_close?(headers) do
    found =
      Enum.any?(headers, fn line ->
        String.downcase(line) |> String.contains?("connection: close")
      end)

    if found, do: Logger.info("[connection_close] header detected, will close connection")
    found
  end
end
