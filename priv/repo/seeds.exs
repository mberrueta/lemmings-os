# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs

alias LemmingsOs.Cities
alias LemmingsOs.Connections
alias LemmingsOs.Departments
alias LemmingsOs.Knowledge
alias LemmingsOs.Knowledge.SourceFiles, as: KnowledgeSourceFiles
alias LemmingsOs.Lemmings
alias LemmingsOs.Repo
alias LemmingsOs.Worlds

world_attrs = %{
  slug: "demo_world",
  name: "Demo World",
  status: "ok",
  last_import_status: "ok",
  bootstrap_source: "seed",
  bootstrap_path: "priv/default.world.yaml"
}

city_attrs = %{
  slug: "demo_city",
  name: "Demo City",
  node_name: "demo_city@localhost",
  host: "127.0.0.1",
  distribution_port: 9110,
  epmd_port: 4371,
  status: "active"
}

department_attrs = %{
  slug: "sales_demo",
  name: "Sales Demo",
  status: "active",
  notes: "Demo sales workflow with manager-led delegation.",
  tags: ["sales", "demo"]
}

sales_manager_instructions = """
You are the Sales Department Manager.

Your job is to understand the user's commercial request and delegate work to the right specialist lemmings.

You must not do operational work yourself unless the request is trivial, such as answering what your role is or listing available capabilities.

For quotation, proposal, customer email, sales research, document generation, or customer memory tasks, delegate.

Use the Available Lemming Calls section provided by the runtime to decide which specialist can handle each task.

When lemming calls are available, delegate operational work instead of doing it yourself.

Default workflow for quotation requests:
1. Ask sales_knowledge_librarian for relevant templates, prices, policies, brand tone, and customer memories.
2. Ask sales_web_researcher for external facts needed for the quote.
3. Ask sales_quote_specialist to prepare the quotation using the gathered context.
4. Return a concise summary to the user with created files, draft status, assumptions, and missing information.

Never ask sales_knowledge_librarian for current external data such as exchange rates, current public prices, current events, or public web facts.
Use sales_web_researcher for exchange rates, current public prices, current events, travel context, and public web facts.

Never create a final quote yourself if a specialist can do it.
Never claim that a file, PDF, memory, or Gmail draft exists unless a specialist reported successful creation.
"""

sales_knowledge_librarian_instructions = """
You are the Sales Knowledge Librarian.

Your job is to retrieve and summarize internal sales knowledge.

Use available knowledge sources, memories, reference files, templates, price lists, company policies, and prior examples.

When asked for quotation support, return:
- relevant price list items
- recommended template
- commercial terms
- brand/tone guidance
- customer memories, if available
- missing internal information

Do not browse the web.
Do not generate PDFs.
Do not create Gmail drafts.
Do not invent prices or policies. If something is not found, say it clearly.
"""

sales_web_researcher_instructions = """
You are the Sales Web Researcher.

Your job is to gather external information useful for sales quotations and commercial proposals.

Focus only on sales-relevant facts, such as:
- exchange rates
- public market prices
- destination or logistics information
- local events that may affect price or availability
- supplier/public references
- travel context
- competitor/package references when useful

Do not go off-topic.
Do not write the quotation.
Do not create files.
Do not create emails.

Return concise findings with:
- fact
- source URL if available
- date or freshness note
- confidence level
- how the fact affects the quotation
"""

sales_quote_specialist_instructions = """
You are the Sales Quote Specialist.

Your job is to prepare complete customer quotations.

You may use internal knowledge, templates, price lists, customer memories, and provided web research to create a professional quotation.

For each quotation:
1. Identify the customer, destination/service, requested items, quantities, dates or duration, and currency.
2. Retrieve or use the relevant internal price list and quotation template.
   - Start with a broad department-scoped knowledge.search query. Do not use guessed tags or exact source types on the first search unless the request provides them.
   - If a broad search returns no prices and the user explicitly allowed placeholders such as `$ XXX.XX`, continue the quotation with those placeholders.
   - If placeholders were not explicitly allowed and required prices are missing, ask for clarification or report missing knowledge before producing priced documents.
3. Apply external facts provided by the manager or sales_web_researcher, such as exchange rates.
4. Prepare a Markdown quotation file.
5. Convert it to HTML when needed.
6. Generate a PDF when requested.
7. Create a Gmail draft when explicitly requested.

Never send emails.
Only create Gmail drafts.
Do not browse the web directly.
Do not invent prices. If internal prices are missing and placeholders were allowed, use `$ XXX.XX` and mark them as assumptions/missing information. If placeholders were not allowed, ask the manager for clarification.
Always report:
- files created
- PDF created or not
- Gmail draft created or not
- assumptions used
- missing information
"""

lemming_attrs = [
  %{
    slug: "sales_manager",
    name: "Sales Manager",
    status: "active",
    collaboration_role: "manager",
    description: "Delegates sales tasks to specialist lemmings.",
    instructions: sales_manager_instructions,
    models_config: %{
      "profiles" => %{
        "primary" => %{
          "provider" => "ollama",
          "model" => "qwen3.5:latest"
        }
      }
    },
    tools_config: %{
      "allowed_tools" => ["lemming.call"],
      "denied_tools" => [
        "fs.read_text_file",
        "fs.write_text_file",
        "web.search",
        "web.fetch",
        "knowledge.search",
        "knowledge.read",
        "knowledge.store",
        "documents.markdown_to_html",
        "documents.print_to_pdf",
        "email.create_draft"
      ]
    }
  },
  %{
    slug: "sales_knowledge_librarian",
    name: "Sales Knowledge Librarian",
    status: "active",
    collaboration_role: "worker",
    description:
      "internal sales knowledge, memories, templates, price lists, policies, prior examples.",
    instructions: sales_knowledge_librarian_instructions,
    models_config: %{
      "profiles" => %{
        "primary" => %{
          "provider" => "ollama",
          "model" => "qwen3.5:latest"
        }
      }
    },
    tools_config: %{
      "allowed_tools" => [
        "knowledge.search",
        "knowledge.read",
        "knowledge.store",
        "fs.read_text_file"
      ],
      "denied_tools" => [
        "web.search",
        "web.fetch",
        "documents.markdown_to_html",
        "documents.print_to_pdf",
        "email.create_draft"
      ]
    }
  },
  %{
    slug: "sales_web_researcher",
    name: "Sales Web Researcher",
    status: "active",
    collaboration_role: "worker",
    description:
      "external sales-related research such as exchange rates, public prices, market references, events, logistics, and travel context.",
    instructions: sales_web_researcher_instructions,
    models_config: %{
      "profiles" => %{
        "primary" => %{
          "provider" => "ollama",
          "model" => "qwen3.5:latest"
        }
      }
    },
    tools_config: %{
      "allowed_tools" => ["web.search", "web.fetch"],
      "denied_tools" => [
        "fs.read_text_file",
        "fs.write_text_file",
        "knowledge.store",
        "documents.markdown_to_html",
        "documents.print_to_pdf",
        "email.create_draft"
      ]
    }
  },
  %{
    slug: "sales_quote_specialist",
    name: "Sales Quote Specialist",
    status: "active",
    collaboration_role: "worker",
    description:
      "prepares complete customer quotations, including document files and Gmail drafts.",
    instructions: sales_quote_specialist_instructions,
    models_config: %{
      "profiles" => %{
        "primary" => %{
          "provider" => "ollama",
          "model" => "qwen3.5:latest"
        }
      }
    },
    tools_config: %{
      "allowed_tools" => [
        "fs.read_text_file",
        "fs.write_text_file",
        "knowledge.search",
        "knowledge.read",
        "documents.markdown_to_html",
        "documents.print_to_pdf",
        "email.create_draft"
      ],
      "denied_tools" => ["web.search", "web.fetch", "knowledge.store"]
    }
  }
]

source_file_seeds = [
  %{
    slug: "company_profile",
    filename: "company_profile.md",
    title: "Company Profile",
    source_file_type: "company_knowledge",
    content: """
    # Entre Mundos Travel — Company Profile

    Default quote language: Portuguese
    Tone: friendly, professional, concise
    Currency for customer-facing totals: BRL
    Quote validity: 7 days
    Payment terms: 50% upfront, 50% before travel
    Human approval: all emails must be sent manually by a human from Gmail
    """
  },
  %{
    slug: "price_list",
    filename: "price_list.md",
    title: "Price List",
    source_file_type: "price_list",
    content: """
    # Demo Price List

    ## Buenos Aires Package Base Prices

    - Hotel 3-star, per night, double room: USD 85
    - Hotel 4-star, per night, double room: USD 140
    - Airport transfer, per group: USD 45
    - City tour, per adult: USD 35
    - City tour, per child: USD 20
    - Tango dinner experience, per adult: USD 75
    - Food tour, per adult: USD 55
    - Service fee: 12%

    ## Default Rules

    - Children under 12 use child pricing when available.
    - If a requested item is missing from the price list, mark it as an assumption.
    - Convert USD to BRL using the exchange rate supplied by sales_web_researcher.
    """
  }
]

reference_file_seeds = [
  %{
    slug: "quote_template",
    filename: "quote_template.md",
    title: "Quote Template",
    reference_ref: "kref:sales_demo_quote_template",
    reference_file_type: "quote_template",
    content: """
    # Cotação de Viagem

    Cliente: {{client_name}}
    Destino: {{destination}}
    Período: {{dates_or_duration}}
    Viajantes: {{travelers}}

    ## Resumo

    {{summary}}

    ## Itens incluídos

    {{items}}

    ## Pesquisa utilizada

    {{research_notes}}

    ## Valores

    {{pricing_table}}

    ## Total estimado

    {{total}}

    ## Condições

    - Cotação válida por 7 dias.
    - Valores sujeitos à disponibilidade.
    - Pagamento: 50% na reserva, 50% antes da viagem.
    - Esta cotação é uma estimativa para aprovação humana antes do envio final.
    """
  },
  %{
    slug: "email_examples",
    filename: "email_examples.md",
    title: "Email Examples",
    reference_ref: "kref:sales_demo_email_examples",
    reference_file_type: "email_examples",
    content: """
    # Email Example

    Subject style:
    Cotação de viagem para {{destination}} - {{client_name}}

    Body style:
    Olá {{client_name}},

    preparamos uma cotação personalizada para sua viagem.

    Segue em anexo a proposta com os itens solicitados, condições comerciais e valores estimados.

    Ficamos à disposição para ajustar datas, categoria de hotel ou experiências incluídas.

    Atenciosamente,
    Entre Mundos Travel
    """
  }
]

customer_memory_seeds = [
  %{
    customer_name: "João Silva",
    customer_email: "joao.silva@example.com",
    items: [
      %{
        key: "hotel_preference",
        content: "João usually prefers 4-star hotels."
      },
      %{
        key: "pricing_preference",
        content: "João likes clear itemized pricing before approving a trip."
      },
      %{
        key: "family_context",
        content: "João is traveling with family and prefers child-friendly activities."
      },
      %{
        key: "language_preference",
        content: "João prefers communication in Portuguese."
      },
      %{
        key: "value_sensitivity",
        content:
          "João is price-sensitive but accepts premium options when the value is clearly explained."
      }
    ]
  },
  %{
    customer_name: "Mariana Costa",
    customer_email: "mariana.costa@example.com",
    items: [
      %{
        key: "hotel_preference",
        content: "Mariana prefers boutique hotels and cultural experiences."
      },
      %{
        key: "package_preference",
        content: "Mariana dislikes generic tourist packages."
      },
      %{
        key: "proposal_style",
        content: "Mariana likes short, elegant proposals with strong visual presentation."
      },
      %{
        key: "experience_focus",
        content: "Mariana often asks for gastronomy, art, music, and local-history experiences."
      },
      %{
        key: "tone_preference",
        content: "Mariana prefers a more premium tone and does not want the quote to feel cheap."
      }
    ]
  },
  %{
    customer_name: "Carlos Pereira",
    customer_email: "carlos.pereira@example.com",
    items: [
      %{
        key: "travel_context",
        content: "Carlos usually travels for business and values efficiency."
      },
      %{
        key: "itinerary_preference",
        content:
          "Carlos prefers direct flights, airport transfers, and hotels near business areas."
      },
      %{
        key: "email_style",
        content: "Carlos wants concise emails with only the essential details."
      },
      %{
        key: "billing_preference",
        content: "Carlos often needs invoices or clearly separated service fees."
      },
      %{
        key: "approval_preference",
        content:
          "Carlos prefers fast approval options and dislikes long back-and-forth conversations."
      }
    ]
  }
]

gmail_connection_config = %{
  "provider" => "gmail",
  "account_email" => "$GMAIL_ACCOUNT_EMAIL_DEMO_WORLD",
  "scopes" => ["https://www.googleapis.com/auth/gmail.compose"],
  "client_id" => "$GMAIL_CLIENT_ID",
  "client_secret" => "$GMAIL_CLIENT_SECRET",
  "refresh_token" => "$GMAIL_REFRESH_TOKEN_DEMO_WORLD"
}

upsert_world! = fn attrs ->
  case Worlds.upsert_world(attrs) do
    {:ok, world} ->
      world

    {:error, changeset} ->
      raise "failed to upsert demo world: #{inspect(changeset.errors)}"
  end
end

upsert_city! = fn world, attrs ->
  case Cities.get_city_by_slug(world, attrs.slug) do
    nil ->
      case Cities.create_city(world, attrs) do
        {:ok, city} -> city
        {:error, changeset} -> raise "failed to create demo city: #{inspect(changeset.errors)}"
      end

    city ->
      case Cities.update_city(city, attrs) do
        {:ok, updated_city} -> updated_city
        {:error, changeset} -> raise "failed to update demo city: #{inspect(changeset.errors)}"
      end
  end
end

upsert_department! = fn city, attrs ->
  case Departments.get_department_by_slug(city, attrs.slug) do
    nil ->
      case Departments.create_department(city, attrs) do
        {:ok, department} ->
          department

        {:error, changeset} ->
          raise "failed to create demo department: #{inspect(changeset.errors)}"
      end

    department ->
      case Departments.update_department(department, attrs) do
        {:ok, updated_department} ->
          updated_department

        {:error, changeset} ->
          raise "failed to update demo department: #{inspect(changeset.errors)}"
      end
  end
end

upsert_lemming! = fn world, city, department, attrs ->
  case Lemmings.get_lemming_by_slug(department, attrs.slug) do
    nil ->
      case Lemmings.create_lemming(world, city, department, attrs) do
        {:ok, lemming} ->
          lemming

        {:error, changeset} ->
          raise "failed to create lemming #{attrs.slug}: #{inspect(changeset.errors)}"
      end

    lemming ->
      case Lemmings.update_lemming(lemming, attrs) do
        {:ok, updated_lemming} ->
          updated_lemming

        {:error, changeset} ->
          raise "failed to update lemming #{attrs.slug}: #{inspect(changeset.errors)}"
      end
  end
end

upsert_source_file! = fn department, seed ->
  summary_content = "Seeded sales demo source file: #{seed.filename}"

  existing =
    department
    |> Knowledge.list_source_files()
    |> Enum.find(fn source_file ->
      source_file.original_filename == seed.filename
    end)

  case existing do
    nil ->
      tmp_path = Path.join(System.tmp_dir!(), "lemmings_os_#{seed.slug}.md")
      File.write!(tmp_path, seed.content)
      size_bytes = byte_size(seed.content)

      attrs = %{
        title: seed.title,
        content: summary_content,
        tags: ["sales_demo", seed.slug],
        source_file_type: seed.source_file_type,
        original_filename: seed.filename,
        content_type: "text/markdown",
        size_bytes: size_bytes,
        metadata: %{"seed_slug" => seed.slug}
      }

      case Knowledge.create_source_file_upload(department, attrs, tmp_path) do
        {:ok, %{source_file: source_file}} ->
          source_file

        {:error, changeset_or_reason} ->
          raise "failed to create source file #{seed.slug}: #{inspect(changeset_or_reason)}"
      end

    source_file ->
      case Knowledge.update_source_file_metadata(department, source_file, %{
             title: seed.title,
             tags: ["sales_demo", seed.slug],
             source_file_type: seed.source_file_type,
             metadata: %{"seed_slug" => seed.slug}
           }) do
        {:ok, %{source_file: updated_source_file}} ->
          updated_source_file

        {:error, changeset_or_reason} ->
          raise "failed to update source file #{seed.slug}: #{inspect(changeset_or_reason)}"
      end
  end
end

ensure_source_file_ready! = fn source_file ->
  source_file = Repo.preload(source_file, :knowledge_item)

  if source_file.knowledge_item.status != "ready" do
    case KnowledgeSourceFiles.run_source_file_indexing(source_file.id) do
      :ok ->
        :ok

      {:error, reason} ->
        raise "failed to index seeded source file #{source_file.id}: #{inspect(reason)}"
    end
  end
end

upsert_reference_file! = fn world, seed ->
  summary_content = "Seeded sales demo reference file: #{seed.filename}"

  existing =
    world
    |> Knowledge.list_reference_files(status: "active")
    |> Enum.find(&(&1.reference_ref == seed.reference_ref))

  case existing do
    nil ->
      tmp_path = Path.join(System.tmp_dir!(), "lemmings_os_#{seed.slug}.md")
      File.write!(tmp_path, seed.content)
      size_bytes = byte_size(seed.content)

      attrs = %{
        title: seed.title,
        content: summary_content,
        tags: ["sales_demo", seed.slug],
        reference_ref: seed.reference_ref,
        reference_file_type: seed.reference_file_type,
        original_filename: seed.filename,
        content_type: "text/markdown",
        size_bytes: size_bytes
      }

      case Knowledge.create_reference_file_upload(world, attrs, tmp_path) do
        {:ok, _created} ->
          :ok

        {:error, changeset_or_reason} ->
          raise "failed to create reference file #{seed.slug}: #{inspect(changeset_or_reason)}"
      end

    existing_file ->
      case Knowledge.update_reference_file_metadata(world, existing_file, %{
             title: seed.title,
             content: summary_content,
             tags: ["sales_demo", seed.slug],
             reference_file_type: seed.reference_file_type
           }) do
        {:ok, _updated} ->
          :ok

        {:error, changeset_or_reason} ->
          raise "failed to update reference file #{seed.slug}: #{inspect(changeset_or_reason)}"
      end
  end
end

archive_incorrect_reference_files! = fn world ->
  world
  |> Knowledge.list_reference_files()
  |> Enum.filter(
    &(&1.reference_ref in ["kref:sales_demo_company_profile", "kref:sales_demo_price_list"])
  )
  |> Enum.each(fn reference_file ->
    case Knowledge.archive_reference_file(world, reference_file) do
      {:ok, _archived} -> :ok
      {:error, reason} -> raise "failed to archive incorrect reference file: #{inspect(reason)}"
    end
  end)
end

upsert_customer_memory! = fn department, seed, memory ->
  key = memory.key
  email = seed.customer_email
  name = seed.customer_name

  title = "[demo_seed][sales_demo][customer_memory] #{email} :: #{key}"

  attrs = %{
    title: title,
    content: "#{name} (#{email}): #{memory.content}",
    tags: [
      "sales_demo",
      "customer_memory",
      "demo_seed",
      "entity_type:customer",
      "customer_email:#{email}",
      "memory_key:#{key}"
    ]
  }

  existing =
    department
    |> Knowledge.list_memories(status: "active", source: "user")
    |> Enum.find(&(&1.title == title))

  case existing do
    nil ->
      case Knowledge.create_memory(department, attrs) do
        {:ok, _memory} ->
          :ok

        {:error, reason} ->
          raise "failed to create customer memory #{email}/#{key}: #{inspect(reason)}"
      end

    memory_item ->
      case Knowledge.update_memory(department, memory_item, attrs) do
        {:ok, _memory} ->
          :ok

        {:error, reason} ->
          raise "failed to update customer memory #{email}/#{key}: #{inspect(reason)}"
      end
  end
end

upsert_gmail_connection! = fn world, config ->
  attrs = %{type: "gmail", status: "enabled", config: config}

  case Connections.get_connection_by_type(world, "gmail") do
    nil ->
      case Connections.create_connection(world, attrs) do
        {:ok, _connection} ->
          :ok

        {:error, changeset_or_reason} ->
          raise "failed to create gmail connection: #{inspect(changeset_or_reason)}"
      end

    connection ->
      case Connections.update_connection(world, connection, attrs) do
        {:ok, _connection} ->
          :ok

        {:error, changeset_or_reason} ->
          raise "failed to update gmail connection: #{inspect(changeset_or_reason)}"
      end
  end
end

prune_other_worlds! = fn demo_world ->
  Worlds.list_worlds()
  |> Enum.reject(&(&1.id == demo_world.id))
  |> Enum.each(&Repo.delete!/1)
end

prune_other_cities! = fn world, demo_city ->
  world
  |> Cities.list_cities()
  |> Enum.reject(&(&1.id == demo_city.id))
  |> Enum.each(&Repo.delete!/1)
end

prune_other_departments! = fn demo_city, demo_department ->
  demo_city
  |> Departments.list_departments()
  |> Enum.reject(&(&1.id == demo_department.id))
  |> Enum.each(&Repo.delete!/1)
end

prune_other_lemmings! = fn demo_department, keep_slugs ->
  demo_department
  |> Lemmings.list_lemmings()
  |> Enum.reject(&(&1.slug in keep_slugs))
  |> Enum.each(&Repo.delete!/1)
end

prune_other_world_connections! = fn world ->
  world
  |> Connections.list_connections()
  |> Enum.reject(&(&1.type == "gmail"))
  |> Enum.each(fn connection ->
    case Connections.delete_connection(world, connection) do
      {:ok, _deleted} ->
        :ok

      {:error, reason} ->
        raise "failed to prune world connection #{connection.id}: #{inspect(reason)}"
    end
  end)
end

world = upsert_world!.(world_attrs)
prune_other_worlds!.(world)

city = upsert_city!.(world, city_attrs)
prune_other_cities!.(world, city)

department = upsert_department!.(city, department_attrs)
prune_other_departments!.(city, department)

Enum.each(lemming_attrs, fn attrs ->
  upsert_lemming!.(world, city, department, attrs)
end)

prune_other_lemmings!.(department, Enum.map(lemming_attrs, & &1.slug))

archive_incorrect_reference_files!.(world)

Enum.each(source_file_seeds, fn seed ->
  seed
  |> then(&upsert_source_file!.(department, &1))
  |> then(fn source_file ->
    ensure_source_file_ready!.(source_file)
  end)
end)

Enum.each(reference_file_seeds, fn seed ->
  upsert_reference_file!.(world, seed)
end)

Enum.each(customer_memory_seeds, fn seed ->
  Enum.each(seed.items, fn memory ->
    upsert_customer_memory!.(department, seed, memory)
  end)
end)

upsert_gmail_connection!.(world, gmail_connection_config)
prune_other_world_connections!.(world)

if Mix.env() != :test or System.get_env("SEEDS_VERBOSE") in ["1", "true"] do
  IO.puts(
    "Seeded demo topology: world=demo_world cities=1 departments=1 lemmings=4 source_files=2 reference_files=2 customer_memories=15"
  )
end
