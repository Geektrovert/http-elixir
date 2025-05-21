defmodule Routes.UserAgent do
  require Logger

  def get(_path, req) do
    Logger.info("[route_entry] module=UserAgent method=GET path=/user-agent")

    user_agent =
      req.headers
      |> Enum.find(fn line -> String.starts_with?(line, "User-Agent: ") end)
      |> case do
        nil -> ""
        line -> String.replace_prefix(line, "User-Agent: ", "")
      end

    accept_encoding = Utils.get_header(req.headers, "Accept-Encoding") || ""

    {body, content_type, encoding} =
      Utils.compress_if_requested(user_agent, "text/plain", accept_encoding)

    {200, "OK", body, content_type, encoding}
  end

  def post(_path, _req) do
    {405, "Method Not Allowed", "", "text/plain"}
  end
end
