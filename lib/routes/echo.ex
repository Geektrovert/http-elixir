defmodule Routes.Echo do
  require Logger

  def get(path, req) do
    Logger.info("[route_entry] module=Echo method=GET path=#{path}")
    message = String.replace_prefix(path, "/echo/", "")
    accept_encoding = Utils.get_header(req.headers, "Accept-Encoding") || ""

    {body, content_type, encoding} =
      Utils.compress_if_requested(message, "text/plain", accept_encoding)

    {200, "OK", body, content_type, encoding}
  end

  def post(_path, _req) do
    {405, "Method Not Allowed", "", "text/plain"}
  end
end
