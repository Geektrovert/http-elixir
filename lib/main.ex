defmodule Server do
  alias Utils
  require Logger

  # Set Logger format at runtime since no config file is present
  Logger.configure_backend(:console, format: "[$time] [$level] $message\n")

  def main(args) do
    _ = [
      Routes.Root.module_info(),
      Routes.Echo.module_info(),
      Routes.Files.module_info(),
      Routes.UserAgent.module_info(),
      Routes.NotFound.module_info()
    ]

    {opts, _, _} = OptionParser.parse(args, switches: [directory: :string])
    directory = opts[:directory] || "."
    Application.put_env(:server, :directory, directory)
    Logger.info("[main] Using file directory: #{directory}")

    # Start your supervision tree here
    children = [
      {Server.Listener, []}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)

    Process.sleep(:infinity)
  end

  def handle_client(client) do
    Logger.info("[client_connect] Accepted new client connection")
    :inet.setopts(client, [{:active, false}])
    loop_handle_requests(client, "")
    :gen_tcp.close(client)
    Logger.info("[client_disconnect] Closed client connection")
  end

  defp loop_handle_requests(client, leftover) do
    case :gen_tcp.recv(client, 0) do
      {:ok, data} ->
        buffer = leftover <> data

        case Utils.parse_request(buffer) do
          {:ok, method, path, headers, body, rest} ->
            Logger.info("[request] method=#{method} path=#{path}")
            close? = Utils.connection_close?(headers)
            handle_request(method, path, headers, body, client)
            if close?, do: :ok, else: loop_handle_requests(client, rest)

          :incomplete ->
            loop_handle_requests(client, buffer)

          :error ->
            Logger.info("[malformed_request] closing connection")
            :ok
        end

      {:error, _} ->
        :ok
    end
  end

  def handle_request(method, path, headers, body, client) do
    req = %{headers: headers, body: body}
    mod = route_module_from_path(path)
    fun = String.downcase(method)

    Logger.info("[route_dispatch] module=#{inspect(mod)} function=#{fun}")

    IO.inspect({mod, fun, function_exported?(mod, String.to_atom(fun), 2)},
      label: "Module, fun, function_exported?"
    )

    result =
      try do
        cond do
          not Code.ensure_loaded?(mod) ->
            Logger.info("[not_found] module=#{inspect(mod)} not loaded")
            {404, "Not Found", "", "text/plain"}

          not function_exported?(mod, String.to_atom(fun), 2) ->
            Logger.info("[method_not_allowed] module=#{inspect(mod)} function=#{fun}")
            {405, "Method Not Allowed", "", "text/plain"}

          true ->
            apply(mod, String.to_atom(fun), [path, req])
        end
      rescue
        UndefinedFunctionError ->
          Logger.info(
            "[not_found] module=#{inspect(mod)} function=#{fun} (UndefinedFunctionError)"
          )

          {404, "Not Found", "", "text/plain"}

        ArgumentError ->
          Logger.info("[not_found] module=#{inspect(mod)} function=#{fun} (ArgumentError)")
          {404, "Not Found", "", "text/plain"}

        _ ->
          Logger.info("[not_found] module=#{inspect(mod)} function=#{fun} (Other error)")
          {404, "Not Found", "", "text/plain"}
      end

    case result do
      {status, status_text, resp_body, content_type, encoding} ->
        Logger.info(
          "[response] status=#{status} content_type=#{content_type} encoding=#{encoding}"
        )

        Utils.send_response(client, "#{status} #{status_text}", resp_body, content_type, encoding)

      {status, status_text, resp_body, content_type} ->
        Logger.info("[response] status=#{status} content_type=#{content_type}")
        Utils.send_response(client, "#{status} #{status_text}", resp_body, content_type)
    end
  end

  defp route_module_from_path(path) do
    segments = String.split(path, "/", trim: true)

    mod_name =
      case segments do
        [] -> "Root"
        [seg | _] -> Macro.camelize(String.replace(seg, "-", "_"))
      end

    Module.concat(Routes, mod_name)
  end
end
