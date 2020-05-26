defmodule Matches.AuthPlug do
  import Plug.Conn

  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    #doar exemplu!
    #https://devhints.io/phoenix-conn
    token = conn
            |> get_req_header("authorization")
            |> List.first()
            |> String.split(" ")
            |> List.last()

    case Matches.Token.verify_and_validate(token) do
      {:ok, _} -> conn
      {:error, _} -> conn |> forbidden
    end
  end

  defp forbidden(conn) do
    send_resp(conn, 401, "Unauthorized!") |> halt
  end
end
