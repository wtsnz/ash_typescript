# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.NestedQueryOptsActorTest do
  @moduledoc """
  Regression coverage for nested relationship envelopes
  (`%{"comments" => %{"fields" => [...], ...}}`) being loaded without the
  request's actor.

  The envelope used to be built with `Ash.Query.for_read/2` at parse time. A
  query that is already validated for an action is returned unchanged when Ash
  loads the relationship, so the parent's actor and `authorize?` never reached
  it. Policies on the related resource then saw an anonymous request: under
  `authorize :by_default` permitted records went missing, and under
  `authorize :when_requested` the related read was not authorized at all.

  The shared test resources have no actor-dependent policies, so the domains,
  resources and manifest are declared inline (as in
  `AshTypescript.EmbeddedGenericActionReturnTest`) to keep the committed
  `test/ts` fixtures untouched.
  """

  # Mutates the global :manifest config, so must not run async.
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc
  alias AshTypescript.Test.TestHelpers

  defmodule Comment do
    use Ash.Resource,
      domain: AshTypescript.Rpc.NestedQueryOptsActorTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer],
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "ActorTestComment"
    end

    attributes do
      uuid_primary_key :id
      attribute :body, :string, public?: true
      attribute :internal, :boolean, public?: true, allow_nil?: false, default: false
    end

    relationships do
      belongs_to :ticket, AshTypescript.Rpc.NestedQueryOptsActorTest.Ticket do
        public? true
        attribute_writable? true
      end
    end

    actions do
      defaults create: [:body, :internal, :ticket_id]

      read :read do
        primary? true
        pagination offset?: true, required?: false
      end

      read :public do
        filter expr(internal == false)
      end
    end

    policies do
      policy action_type(:read) do
        authorize_if actor_attribute_equals(:role, "agent")
        authorize_if expr(internal == false)
      end

      policy action_type(:create) do
        authorize_if always()
      end
    end
  end

  defmodule Ticket do
    use Ash.Resource,
      domain: AshTypescript.Rpc.NestedQueryOptsActorTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "ActorTestTicket"
    end

    attributes do
      uuid_primary_key :id
      attribute :title, :string, public?: true
    end

    relationships do
      has_many :comments, AshTypescript.Rpc.NestedQueryOptsActorTest.Comment do
        public? true
      end

      has_many :public_comments, AshTypescript.Rpc.NestedQueryOptsActorTest.Comment do
        public? true
        read_action :public
      end
    end

    actions do
      defaults [:read, create: [:title], update: [:title]]

      read :get_by_id do
        get? true
        argument :id, :uuid, allow_nil?: false
        filter expr(id == ^arg(:id))
      end
    end
  end

  defmodule Domain do
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    typescript_rpc do
      resource AshTypescript.Rpc.NestedQueryOptsActorTest.Ticket do
        rpc_action :actor_test_get_ticket, :get_by_id
        rpc_action :actor_test_update_ticket, :update
      end

      resource AshTypescript.Rpc.NestedQueryOptsActorTest.Comment do
        rpc_action :actor_test_list_comments, :read
      end
    end

    resources do
      resource AshTypescript.Rpc.NestedQueryOptsActorTest.Ticket
      resource AshTypescript.Rpc.NestedQueryOptsActorTest.Comment
    end
  end

  # Same shape as above, in a domain that only authorizes when requested. With
  # an actor present, Ash authorizes the parent read; the related read must be
  # authorized too.
  defmodule WhenRequestedComment do
    use Ash.Resource,
      domain: AshTypescript.Rpc.NestedQueryOptsActorTest.WhenRequestedDomain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer],
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "ActorTestWhenRequestedComment"
    end

    attributes do
      uuid_primary_key :id
      attribute :body, :string, public?: true
      attribute :internal, :boolean, public?: true, allow_nil?: false, default: false
    end

    relationships do
      belongs_to :ticket, AshTypescript.Rpc.NestedQueryOptsActorTest.WhenRequestedTicket do
        public? true
        attribute_writable? true
      end
    end

    actions do
      defaults [:read, create: [:body, :internal, :ticket_id]]
    end

    policies do
      policy action_type(:read) do
        authorize_if actor_attribute_equals(:role, "agent")
        authorize_if expr(internal == false)
      end

      policy action_type(:create) do
        authorize_if always()
      end
    end
  end

  defmodule WhenRequestedTicket do
    use Ash.Resource,
      domain: AshTypescript.Rpc.NestedQueryOptsActorTest.WhenRequestedDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshTypescript.Resource]

    typescript do
      type_name "ActorTestWhenRequestedTicket"
    end

    attributes do
      uuid_primary_key :id
      attribute :title, :string, public?: true
    end

    relationships do
      has_many :comments, AshTypescript.Rpc.NestedQueryOptsActorTest.WhenRequestedComment do
        public? true
        destination_attribute :ticket_id
      end
    end

    actions do
      defaults [:read, create: [:title]]

      read :get_by_id do
        get? true
        argument :id, :uuid, allow_nil?: false
        filter expr(id == ^arg(:id))
      end
    end
  end

  defmodule WhenRequestedDomain do
    use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

    authorization do
      authorize :when_requested
    end

    typescript_rpc do
      resource AshTypescript.Rpc.NestedQueryOptsActorTest.WhenRequestedTicket do
        rpc_action :actor_test_when_requested_get_ticket, :get_by_id
      end

      resource AshTypescript.Rpc.NestedQueryOptsActorTest.WhenRequestedComment do
        rpc_action :actor_test_when_requested_list_comments, :read
      end
    end

    resources do
      resource AshTypescript.Rpc.NestedQueryOptsActorTest.WhenRequestedTicket
      resource AshTypescript.Rpc.NestedQueryOptsActorTest.WhenRequestedComment
    end
  end

  defmodule Manifest do
    use AshTypescript.Manifest,
      otp_app: :ash_typescript,
      domains: [
        AshTypescript.Rpc.NestedQueryOptsActorTest.Domain,
        AshTypescript.Rpc.NestedQueryOptsActorTest.WhenRequestedDomain
      ]
  end

  @agent %{id: "agent-1", role: "agent"}
  @viewer %{id: "viewer-1", role: "viewer"}

  @public_bodies ["public 1", "public 2"]
  @internal_bodies ["internal 1", "internal 2"]
  @all_bodies Enum.sort(@public_bodies ++ @internal_bodies)

  setup do
    TestHelpers.restore_application_env_on_exit([:manifest])
    Application.put_env(:ash_typescript, :manifest, Manifest)
    :ok
  end

  defp create_ticket(ticket_resource, comment_resource) do
    ticket = Ash.create!(ticket_resource, %{title: "Ticket"}, authorize?: false)

    for body <- @public_bodies ++ @internal_bodies do
      Ash.create!(
        comment_resource,
        %{body: body, internal: body in @internal_bodies, ticket_id: ticket.id},
        authorize?: false
      )
    end

    ticket.id
  end

  defp conn_for(actor) do
    Ash.PlugHelpers.set_actor(TestHelpers.build_rpc_conn(), actor)
  end

  defp get_ticket(action, actor, ticket_id, relationship_selection) do
    assert %{"success" => true, "data" => data} =
             Rpc.run_action(:ash_typescript, conn_for(actor), %{
               "action" => action,
               "input" => %{"id" => ticket_id},
               "fields" => ["id", relationship_selection]
             })

    data
  end

  defp bodies(%{"results" => results}), do: bodies(results)
  defp bodies(comments), do: comments |> Enum.map(& &1["body"]) |> Enum.sort()

  describe "authorize :by_default" do
    setup do
      %{ticket_id: create_ticket(Ticket, Comment)}
    end

    test "envelope forms load comments with the request's actor, like the plain list",
         %{ticket_id: ticket_id} do
      plain = get_ticket("actor_test_get_ticket", @agent, ticket_id, %{"comments" => ["body"]})
      assert bodies(plain["comments"]) == @all_bodies

      envelopes = [
        %{"fields" => ["body"]},
        %{"fields" => ["body"], "sort" => "body"},
        %{"fields" => ["body"], "limit" => 50},
        %{"fields" => ["body"], "page" => %{"limit" => 50, "offset" => 0}}
      ]

      for envelope <- envelopes do
        data =
          get_ticket("actor_test_get_ticket", @agent, ticket_id, %{"comments" => envelope})

        assert bodies(data["comments"]) == @all_bodies,
               "envelope #{inspect(envelope)} returned #{inspect(data["comments"])}"
      end

      filtered =
        get_ticket("actor_test_get_ticket", @agent, ticket_id, %{
          "comments" => %{"fields" => ["body"], "filter" => %{"internal" => %{"eq" => true}}}
        })

      assert bodies(filtered["comments"]) == @internal_bodies

      # Order-sensitive, with a limit that actually binds: the first comment by
      # body is internal, so it is only returned if the actor reached the read.
      sorted =
        get_ticket("actor_test_get_ticket", @agent, ticket_id, %{
          "comments" => %{"fields" => ["body"], "sort" => "body", "limit" => 1}
        })

      assert Enum.map(sorted["comments"], & &1["body"]) == ["internal 1"]
    end

    test "an actor without access only gets the permitted comments", %{ticket_id: ticket_id} do
      plain = get_ticket("actor_test_get_ticket", @viewer, ticket_id, %{"comments" => ["body"]})
      assert bodies(plain["comments"]) == @public_bodies

      envelope =
        get_ticket("actor_test_get_ticket", @viewer, ticket_id, %{
          "comments" => %{"fields" => ["body"], "limit" => 50}
        })

      assert bodies(envelope["comments"]) == @public_bodies
    end

    test "envelope uses the relationship's read_action", %{ticket_id: ticket_id} do
      data =
        get_ticket("actor_test_get_ticket", @agent, ticket_id, %{
          "publicComments" => %{"fields" => ["body"], "sort" => "body"}
        })

      assert bodies(data["publicComments"]) == @public_bodies
    end

    test "envelope on a mutation result loads with the request's actor", %{ticket_id: ticket_id} do
      assert %{"success" => true, "data" => data} =
               Rpc.run_action(:ash_typescript, conn_for(@agent), %{
                 "action" => "actor_test_update_ticket",
                 "identity" => ticket_id,
                 "input" => %{"title" => "Updated"},
                 "fields" => ["title", %{"comments" => %{"fields" => ["body"], "limit" => 50}}]
               })

      assert data["title"] == "Updated"
      assert bodies(data["comments"]) == @all_bodies
    end
  end

  describe "authorize :when_requested" do
    setup do
      %{ticket_id: create_ticket(WhenRequestedTicket, WhenRequestedComment)}
    end

    test "envelope does not skip authorization of the related read", %{ticket_id: ticket_id} do
      action = "actor_test_when_requested_get_ticket"

      plain = get_ticket(action, @viewer, ticket_id, %{"comments" => ["body"]})
      assert bodies(plain["comments"]) == @public_bodies

      envelope = get_ticket(action, @viewer, ticket_id, %{"comments" => %{"fields" => ["body"]}})
      assert bodies(envelope["comments"]) == @public_bodies

      agent = get_ticket(action, @agent, ticket_id, %{"comments" => %{"fields" => ["body"]}})
      assert bodies(agent["comments"]) == @all_bodies
    end
  end
end
