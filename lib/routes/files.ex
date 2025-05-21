defmodule Routes.Files do
  require Logger

  def get(path, req) do
    Logger.info("[route_entry] module=Files method=GET path=#{path}")
    accept_encoding = Utils.get_header(req.headers, "Accept-Encoding") || ""
    file_name = String.replace_prefix(path, "/files/", "")
    directory = Application.get_env(:codecrafters_http_server, :directory, ".")
    full_path = Path.join(directory, file_name)

    case File.read(full_path) do
      {:ok, contents} ->
        Logger.info("[file_served] path=#{full_path} size=#{byte_size(contents)}")

        {body, content_type, encoding} =
          Utils.compress_if_requested(contents, "application/octet-stream", accept_encoding)

        {200, "OK", body, content_type, encoding}

      {:error, _} ->
        {404, "Not Found", "", "text/plain"}
    end
  end

  def post(path, req) do
    content_encoding = Utils.get_header(req.headers, "Content-Encoding") || ""
    file_name = String.replace_prefix(path, "/files/", "")
    directory = Application.get_env(:codecrafters_http_server, :directory, ".")
    full_path = Path.join(directory, file_name)
    data = Utils.decompress_req(req.body, content_encoding)

    case File.write(full_path, data) do
      :ok -> {201, "Created", "", "text/plain"}
      _ -> {500, "Internal Server Error", "", "text/plain"}
    end
  end
end
