defmodule Matches.Match do
  use Ecto.Schema

  @primary_key {:MatchedContactId, :id, autogenerate: true}
#  @derive {Poison.Encoder, only: [:name, :age]}
  schema "MatchedContact" do
    field :FirstProfileId, :integer
    field :SecondProfileId, :integer
    field :FirstProfileLike, :boolean
    field :SecondProfileLike, :boolean
    field :MatchDateTime, Ecto.DateTime
  end

end