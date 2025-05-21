defmodule Routes.Root do
  require Logger

  def get(_path, req) do
    Logger.info("[route_entry] module=Root method=GET path=/")
    accept_encoding = Utils.get_header(req.headers, "Accept-Encoding") || ""

    {body, content_type, encoding} =
      Utils.compress_if_requested("", "text/plain", accept_encoding)

    {200, "OK", body, content_type, encoding}
  end

  def post(_path, _req) do
    {405, "Method Not Allowed", "", "text/plain"}
  end
end
