defmodule Matches.Router do
  use Plug.Router
  use Timex
  alias Matches.Match
  import Ecto.Query

#  @skip_token_verification %{jwt_skip: true}
#  @skip_token_verification_view %{view: DogView, jwt_skip: true}
#  @auth_url Application.get_env(:profiles, :auth_url)
#  @api_port Application.get_env(:profiles, :port)
#  @db_table Application.get_env(:profiles, :redb_db)
#  @db_name Application.get_env(:profiles, :redb_db)

  #use Profiles.Auth
  require Logger

  plug(Plug.Logger, log: :debug)

  plug(:match)
#  plug Profiles.AuthPlug
  plug(:dispatch)

  post "/get-matches-by-profile-id" do
    Logger.debug inspect(conn.body_params)

    {current_profile_id} = {
      Map.get(conn.body_params, "current_profile_id", nil)
    }

    matches = Matches.Repo.all(
      from d in Matches.Match,
      where: (d."FirstProfileId" == ^current_profile_id
              or d."SecondProfileId" == ^current_profile_id)
              and d."FirstProfileLike" == true and d."SecondProfileLike" == true)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Poison.encode!(matches))

  end

  post "/get-match" do
    Logger.debug inspect(conn.body_params)

    {current_profile_id, liked_profile_id} = {
      Map.get(conn.body_params, "current_profile_id", nil),
      Map.get(conn.body_params, "liked_profile_id", nil)
    }

    match= Matches.Repo.one(
      from d in Matches.Match,
      where: (d."FirstProfileId" == ^current_profile_id and d."SecondProfileId" == ^liked_profile_id)
      or (d."SecondProfileId" == ^current_profile_id and d."FirstProfileId" == ^liked_profile_id)
    )

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Poison.encode!(match))

  end

  post "/get-recommendation" do
    current_profile_id = Map.get(conn.body_params, "current_profile_id", nil)

    filter_ids_first =  Matches.Repo.all(
      from d in Matches.Match,
      select: d."SecondProfileId",
      where: (d."FirstProfileId" == ^current_profile_id
              and (d."FirstProfileLike" == true or d."FirstProfileLike" == false))
    )

    filter_ids_second =  Matches.Repo.all(
      from d in Matches.Match,
      select: d."FirstProfileId",
      where: (d."SecondProfileId" == ^current_profile_id
              and (d."SecondProfileLike" == true or d."SecondProfileLike" == false))
    )

    filter_ids = Enum.concat(filter_ids_first, filter_ids_second)

    Logger.debug inspect(filter_ids)

    token = conn
            |> get_req_header("authorization")
            |> List.first()
            |> String.split(" ")
            |> List.last()

    url = Application.get_env(:matches, :profile_service_url) <> "/profile/get-recommendations-by-id"

    body = Poison.encode!(
        %{
          "current_profile_id": current_profile_id,
          "filter_ids": filter_ids
        })

    headers = [{"Content-type", "application/json"}, {"authorization", token}]

    resp = HTTPotion.post  url , [body: body, headers: headers]

    Logger.debug inspect(resp)
    profiles = resp.body()
    profiles = Poison.decode!(profiles)
    Logger.debug inspect(profiles)

    profile = Enum.at(profiles, 0)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(201, Poison.encode!(%{:profiles => profile}))
  end



  post "/like" do
    Logger.debug inspect(conn.body_params)

    {current_profile_id, liked_profile_id, like} = {
      Map.get(conn.body_params, "current_profile_id", nil),
      Map.get(conn.body_params, "liked_profile_id", nil),
      Map.get(conn.body_params, "like", nil)
    }

    match_date_time = Ecto.DateTime.utc

    cond do
      is_nil(current_profile_id) ->
        conn
        |> put_status(400)
        |> assign(:jsonapi, %{"error" => "'current_profile_id' field must be provided"})
      is_nil(liked_profile_id) ->
        conn
        |> put_status(400)
        |> assign(:jsonapi, %{"error" => "'liked_profile_id' field must be provided"})
      is_nil(like) ->
        conn
        |> put_status(400)
        |> assign(:jsonapi, %{"error" => "'like' field must be provided"})
      true ->
      matched = Matches.Repo.one(
        from d in Matches.Match,
        select: [d."MatchedContactId", d."FirstProfileId", d."SecondProfileId"],
        where: (d."FirstProfileId" == ^current_profile_id and d."SecondProfileId" == ^liked_profile_id)
        or (d."SecondProfileId" == ^current_profile_id and d."FirstProfileId" == ^liked_profile_id)
      )

      Logger.debug inspect(matched)

      Logger.debug inspect(like)

      if matched == nil do
        case %Match{
          FirstProfileId: current_profile_id,
          SecondProfileId: liked_profile_id,
          FirstProfileLike: like,
          SecondProfileLike: nil,
          MatchDateTime: match_date_time
        } |> Matches.Repo.insert do
          {:ok, new_match} ->
            matched_contact_id = Matches.Repo.one(
              from d in Matches.Match,
              select: d."MatchedContactId",
              where: (d."FirstProfileId" == ^current_profile_id and d."SecondProfileId" == ^liked_profile_id)
              or (d."SecondProfileId" == ^current_profile_id and d."FirstProfileId" == ^liked_profile_id)
            )

            rabbit_url = Application.get_env(:matches, :rabbitmq_host)
            Logger.debug inspect(rabbit_url)

            # AMQP.Connection.open
            # AMQP.Connection.open(options, :undefined)
            case AMQP.Connection.open(rabbit_url) do
              {:ok, connection} ->
                case AMQP.Channel.open(connection) do
                  {:ok, channel} ->
                  AMQP.Queue.declare(channel, "matched_contact_id_#{matched_contact_id}")
                  AMQP.Connection.close(connection)
                  {:error, unkown_host} ->
                  Logger.debug inspect(unkown_host)
              :error ->
                Logger.debug inspect("AMQP connection coould not be established")
                end
            end

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(201, Poison.encode!(%{:data => new_match}))
          :error ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(507, Poison.encode!(%{"error" => "An unexpected error happened"}))
        end
        else
        matched_contact_id = Enum.at(matched, 0)
        first_profile_id = Enum.at(matched, 1)
        second_profile_id = Enum.at(matched, 2)

        update_changes = if second_profile_id == current_profile_id do
          %{SecondProfileLike: like, MatchDateTime: match_date_time}
          else
          %{FirstProfileLike: like, MatchDateTime: match_date_time}
        end

        Logger.debug inspect(matched_contact_id)
        Logger.debug inspect(update_changes)

        case Matches.Repo.get(Matches.Match, matched_contact_id)
        |> Ecto.Changeset.change(update_changes)
        |> Matches.Repo.update() do
          {:ok, new_match} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(201, Poison.encode!(%{:data => new_match}))
          :error ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(507, Poison.encode!(%{"error" => "An unexpected error happened"}))
        end
        end
    end
  end
end

