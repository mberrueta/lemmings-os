# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     LemmingsOs.Repo.insert!(%LemmingsOs.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias LemmingsOs.Cities
alias LemmingsOs.Cities.Runtime, as: RuntimeCities
alias LemmingsOs.Departments
alias LemmingsOs.Lemmings
alias LemmingsOs.SecretBank
alias LemmingsOs.Worlds
alias LemmingsOs.Worlds.World

default_world_attrs = %{
  slug: "local",
  name: "Local World",
  status: "ok",
  last_import_status: "ok",
  bootstrap_source: "seed",
  bootstrap_path: Path.expand("priv/default.world.yaml", File.cwd!())
}

city_plans = [
  %{
    key: :runtime,
    kind: :runtime,
    departments: [
      %{
        slug: "support",
        name: "Support",
        status: "active",
        notes: "Customer-facing support department.",
        tags: ["support", "tier-1"]
      },
      %{
        slug: "platform",
        name: "Platform",
        status: "active",
        notes: "Platform operations and runtime ownership.",
        tags: ["platform", "backend"]
      }
    ]
  },
  %{
    key: :beta,
    kind: :regular,
    attrs: %{
      slug: "beta-city",
      name: "Beta City",
      node_name: "beta@localhost",
      host: "127.0.0.1",
      distribution_port: 9102,
      epmd_port: 4370,
      status: "active"
    },
    departments: [
      %{
        slug: "research",
        name: "Research",
        status: "active",
        notes: "Experiments and model evaluation.",
        tags: ["research", "experiments"]
      },
      %{
        slug: "ops",
        name: "Ops",
        status: "draining",
        notes: "Operational follow-up and incident handling.",
        tags: ["ops", "incident"]
      },
      %{
        slug: "finance",
        name: "Finance",
        status: "active",
        notes: "Budget oversight and cost control.",
        tags: ["finance", "budget"]
      },
      %{
        slug: "quality",
        name: "Quality",
        status: "active",
        notes: "Quality review and release verification.",
        tags: ["quality", "testing"]
      }
    ]
  }
]

lemming_seeds = %{
  {:runtime, "support"} => [
    %{
      slug: "incident-triage",
      name: "Incident Triage",
      status: "active",
      description: "Classifies inbound incidents and routes them to the right team.",
      instructions:
        "Review new incidents, tag urgency, and route them to the correct department.",
      tools_config: %{"allowed_tools" => ["github", "logs"], "denied_tools" => ["shell"]}
    },
    %{
      slug: "customer-follow-up",
      name: "Customer Follow-up",
      status: "draft",
      description: "Prepares customer updates after support triage completes.",
      instructions:
        "Summarize the issue status, identify next actions, and draft a clear customer-facing update.",
      tools_config: %{"allowed_tools" => ["github"], "denied_tools" => ["shell"]}
    }
  ],
  {:runtime, "platform"} => [
    %{
      slug: "deploy-check",
      name: "Deploy Check",
      status: "active",
      description: "Validates deploy readiness before rollout starts.",
      instructions:
        "Review deploy prerequisites, verify environment health, and flag rollout blockers early.",
      tools_config: %{"allowed_tools" => ["logs"], "denied_tools" => ["shell"]}
    },
    %{
      slug: "runtime-watch",
      name: "Runtime Watch",
      status: "active",
      description: "Monitors runtime warnings and summarizes cluster anomalies.",
      instructions:
        "Track runtime issues, cluster repeated symptoms, and escalate suspicious error patterns.",
      tools_config: %{"allowed_tools" => ["logs", "github"], "denied_tools" => ["shell"]}
    },
    %{
      slug: "runbook-editor",
      name: "Runbook Editor",
      status: "archived",
      description: "Maintains runbook drafts and operational remediation notes.",
      instructions:
        "Keep runbooks current, merge validated remediation notes, and archive obsolete guidance.",
      tools_config: %{"allowed_tools" => ["github"], "denied_tools" => ["shell"]}
    }
  ],
  {:beta, "research"} => [
    %{
      slug: "release-notes",
      name: "Release Notes",
      status: "draft",
      description: "Drafts operator-facing release summaries from merged changes.",
      instructions:
        "Scan recent merged work, produce concise release notes, and highlight breaking changes.",
      tools_config: %{"allowed_tools" => ["github"], "denied_tools" => []}
    },
    %{
      slug: "eval-scorer",
      name: "Eval Scorer",
      status: "active",
      description: "Scores experiment outputs and keeps benchmark summaries current.",
      instructions:
        "Compare experiment outputs, score benchmark quality, and summarize meaningful regressions.",
      tools_config: %{"allowed_tools" => ["github", "logs"], "denied_tools" => ["shell"]}
    }
  ],
  {:beta, "ops"} => [
    %{
      slug: "queue-sweeper",
      name: "Queue Sweeper",
      status: "active",
      description: "Keeps operational queues from stalling on untriaged items.",
      instructions:
        "Review pending operational work, remove duplicates, and escalate blocked items quickly.",
      tools_config: %{"allowed_tools" => ["logs"], "denied_tools" => ["shell"]}
    },
    %{
      slug: "handoff-writer",
      name: "Handoff Writer",
      status: "draft",
      description: "Produces structured handoff notes between shifts.",
      instructions:
        "Summarize open incidents, pending actions, and operational risks for the next shift.",
      tools_config: %{"allowed_tools" => ["github"], "denied_tools" => []}
    }
  ],
  {:beta, "finance"} => [
    %{
      slug: "cost-watch",
      name: "Cost Watch",
      status: "active",
      description: "Monitors model and runtime spend against declared budgets.",
      instructions:
        "Compare usage against configured budgets and flag unusual spend before limits are exceeded.",
      tools_config: %{"allowed_tools" => ["logs"], "denied_tools" => ["shell"]}
    },
    %{
      slug: "budget-brief",
      name: "Budget Brief",
      status: "active",
      description: "Builds concise budget summaries for operators.",
      instructions:
        "Summarize budget status, upcoming risks, and the biggest current cost drivers. When the user asks you to create or update a file, use fs.write_text_file with a workspace-relative path instead of only describing the content. When you need external context, use web.search or web.fetch.",
      tools_config: %{
        "allowed_tools" => [
          "fs.read_text_file",
          "fs.write_text_file",
          "web.search",
          "web.fetch"
        ],
        "denied_tools" => []
      }
    },
    %{
      slug: "variance-review",
      name: "Variance Review",
      status: "archived",
      description: "Reviews unusual budget variance after monthly close.",
      instructions:
        "Inspect large budget deltas, explain the likely cause, and record durable follow-up notes.",
      tools_config: %{"allowed_tools" => ["logs"], "denied_tools" => ["shell"]}
    }
  ],
  {:beta, "quality"} => [
    %{
      slug: "qa-reviewer",
      name: "QA Reviewer",
      status: "active",
      description: "Reviews release candidates and validates testing coverage.",
      instructions:
        "Check release readiness, call out gaps in validation coverage, and summarize open defects.",
      tools_config: %{"allowed_tools" => ["github"], "denied_tools" => ["shell"]}
    },
    %{
      slug: "regression-tracker",
      name: "Regression Tracker",
      status: "draft",
      description: "Tracks recurring regressions across recent releases.",
      instructions:
        "Identify repeated regressions, group them by area, and propose the next verification focus.",
      tools_config: %{"allowed_tools" => ["github", "logs"], "denied_tools" => ["shell"]}
    }
  ]
}

create_department! = fn city, attrs ->
  case Departments.create_department(city, attrs) do
    {:ok, department} ->
      department

    {:error, changeset} ->
      raise """
      failed to seed department #{inspect(attrs.name)} for #{inspect(city.slug)}
      #{inspect(changeset.errors)}
      """
  end
end

update_department! = fn department, attrs ->
  case Departments.update_department(department, attrs) do
    {:ok, updated_department} ->
      updated_department

    {:error, changeset} ->
      raise """
      failed to update seeded department #{inspect(attrs.name)} for #{inspect(department.slug)}
      #{inspect(changeset.errors)}
      """
  end
end

create_lemming! = fn world, city, department, attrs ->
  case Lemmings.create_lemming(world, city, department, attrs) do
    {:ok, lemming} ->
      lemming

    {:error, changeset} ->
      raise """
      failed to seed lemming #{inspect(attrs.name)} for #{inspect(department.slug)}
      #{inspect(changeset.errors)}
      """
  end
end

update_lemming! = fn lemming, attrs ->
  case Lemmings.update_lemming(lemming, attrs) do
    {:ok, updated_lemming} ->
      updated_lemming

    {:error, changeset} ->
      raise """
      failed to update seeded lemming #{inspect(attrs.name)} for #{inspect(lemming.slug)}
      #{inspect(changeset.errors)}
      """
  end
end

create_city! = fn world, attrs ->
  case Cities.create_city(world, attrs) do
    {:ok, city} ->
      city

    {:error, changeset} ->
      raise """
      failed to seed city #{inspect(attrs.name)}
      #{inspect(changeset.errors)}
      """
  end
end

update_city! = fn city, attrs ->
  case Cities.update_city(city, attrs) do
    {:ok, updated_city} ->
      updated_city

    {:error, changeset} ->
      raise """
      failed to update seeded city #{inspect(city.slug)}
      #{inspect(changeset.errors)}
      """
  end
end

upsert_primary_city! = fn world, attrs ->
  case Cities.get_city_by_slug(world, "local_city") || List.first(Cities.list_cities(world)) do
    city when not is_nil(city) ->
      # Preserve the first/default city identity as-is on reruns.
      city

    nil ->
      create_city!.(world, attrs)
  end
end

upsert_city_by_slug! = fn world, attrs ->
  case Cities.get_city_by_slug(world, attrs.slug) do
    nil -> create_city!.(world, attrs)
    city -> update_city!.(city, attrs)
  end
end

upsert_department! = fn city, attrs ->
  case Departments.get_department_by_slug(city, attrs.slug) do
    nil -> create_department!.(city, attrs)
    department -> update_department!.(department, attrs)
  end
end

upsert_lemming! = fn world, city, department, attrs ->
  case Lemmings.get_lemming_by_slug(department, attrs.slug) do
    nil -> create_lemming!.(world, city, department, attrs)
    lemming -> update_lemming!.(lemming, attrs)
  end
end

create_sample_secret! = fn world ->
  if SecretBank.list_effective_metadata(world, bank_key: "github.token") == [] do
    {:ok, _metadata} =
      SecretBank.upsert_secret(world, "github.token", "dev_only_mock_github_token")
  end
end

{:ok, world} =
  case Worlds.get_default_world() do
    %World{} = world -> {:ok, world}
    nil -> Worlds.upsert_world(default_world_attrs)
  end

create_sample_secret!.(world)

runtime_city_attrs = RuntimeCities.runtime_city_attrs()

seeded =
  city_plans
  |> Enum.map(fn
    %{key: :runtime, departments: departments} ->
      runtime_city = upsert_primary_city!.(world, runtime_city_attrs)

      seeded_departments =
        Enum.map(departments, fn department_attrs ->
          department = upsert_department!.(runtime_city, department_attrs)

          lemming_seeds
          |> Map.get({:runtime, department.slug}, [])
          |> Enum.each(fn lemming_attrs ->
            upsert_lemming!.(world, runtime_city, department, lemming_attrs)
          end)

          department
        end)

      %{city: runtime_city, departments: seeded_departments}

    %{key: key, attrs: city_attrs, departments: departments} ->
      city = upsert_city_by_slug!.(world, city_attrs)

      seeded_departments =
        Enum.map(departments, fn department_attrs ->
          department = upsert_department!.(city, department_attrs)

          lemming_seeds
          |> Map.get({key, department.slug}, [])
          |> Enum.each(fn lemming_attrs ->
            upsert_lemming!.(world, city, department, lemming_attrs)
          end)

          department
        end)

      %{city: city, departments: seeded_departments}
  end)

department_count =
  seeded
  |> Enum.flat_map(& &1.departments)
  |> length()

lemming_count =
  seeded
  |> Enum.flat_map(fn %{departments: departments} ->
    Enum.flat_map(departments, &Lemmings.list_lemmings/1)
  end)
  |> length()

seed_summary =
  "Seeded world #{world.slug} with #{length(seeded)} cities, #{department_count} departments, #{lemming_count} lemmings, and sample Secret Bank metadata."

if Mix.env() != :test or System.get_env("SEEDS_VERBOSE") in ["1", "true"] do
  IO.puts(seed_summary)
end
