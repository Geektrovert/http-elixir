defmodule Routes.NotFound do
  require Logger

  def get(_path, req) do
    Logger.info("[route_entry] module=NotFound method=GET path=*")
    accept_encoding = Utils.get_header(req.headers, "Accept-Encoding") || ""

    {body, content_type, encoding} =
      Utils.compress_if_requested("", "text/plain", accept_encoding)

    {404, "Not Found", body, content_type, encoding}
  end

  def post(_path, _req), do: {404, "Not Found", "", "text/plain"}
  def put(_path, _req), do: {404, "Not Found", "", "text/plain"}
  def delete(_path, _req), do: {404, "Not Found", "", "text/plain"}
end
