> ## Documentation Index
> Fetch the complete documentation index at: https://docs.langchain.com/llms.txt
> Use this file to discover all available pages before exploring further.

# Long-term memory

> Add long-term memory to LangChain agents to store and recall data across conversations and sessions

Long-term memory lets your agent store and recall information across different conversations and sessions.
Unlike [short-term memory](/oss/javascript/langchain/short-term-memory), which is scoped to a single thread, long-term memory persists across threads and can be recalled at any time.

Long-term memory is built on [LangGraph stores](/oss/javascript/langgraph/stores), which save data as JSON documents organized by namespace and key.

## Usage

To add long-term memory to an agent, create a store and pass it to [`create_agent`](https://reference.langchain.com/javascript/langchain/index/createAgent):

<Tabs>
  <Tab title="InMemoryStore">
    <CodeGroup>
      ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import { createAgent } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production use.
      const store = new InMemoryStore();

      const agent = createAgent({
        model: "google:gemini-3.6-flash",
        tools: [],
        store,
      });
      ```

      ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import { createAgent } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production use.
      const store = new InMemoryStore();

      const agent = createAgent({
        model: "openai:gpt-5.5",
        tools: [],
        store,
      });
      ```

      ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import { createAgent } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production use.
      const store = new InMemoryStore();

      const agent = createAgent({
        model: "anthropic:claude-sonnet-5",
        tools: [],
        store,
      });
      ```

      ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import { createAgent } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production use.
      const store = new InMemoryStore();

      const agent = createAgent({
        model: "openrouter:z-ai/glm-5.2",
        tools: [],
        store,
      });
      ```

      ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import { createAgent } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production use.
      const store = new InMemoryStore();

      const agent = createAgent({
        model: "fireworks:accounts/fireworks/models/glm-5p2",
        tools: [],
        store,
      });
      ```

      ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import { createAgent } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production use.
      const store = new InMemoryStore();

      const agent = createAgent({
        model: "baseten:zai-org/GLM-5.2",
        tools: [],
        store,
      });
      ```

      ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import { createAgent } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production use.
      const store = new InMemoryStore();

      const agent = createAgent({
        model: "ollama:north-mini-code-1.0",
        tools: [],
        store,
      });
      ```
    </CodeGroup>
  </Tab>

  <Tab title="PostgreSQL">
    ```shell theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    npm install @langchain/langgraph-checkpoint-postgres
    ```

    <CodeGroup>
      ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import { createAgent } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const agent = createAgent({
        model: "google:gemini-3.6-flash",
        tools: [],
        store,
      });
      ```

      ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import { createAgent } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const agent = createAgent({
        model: "openai:gpt-5.5",
        tools: [],
        store,
      });
      ```

      ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import { createAgent } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const agent = createAgent({
        model: "anthropic:claude-sonnet-5",
        tools: [],
        store,
      });
      ```

      ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import { createAgent } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const agent = createAgent({
        model: "openrouter:z-ai/glm-5.2",
        tools: [],
        store,
      });
      ```

      ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import { createAgent } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const agent = createAgent({
        model: "fireworks:accounts/fireworks/models/glm-5p2",
        tools: [],
        store,
      });
      ```

      ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import { createAgent } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const agent = createAgent({
        model: "baseten:zai-org/GLM-5.2",
        tools: [],
        store,
      });
      ```

      ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import { createAgent } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const agent = createAgent({
        model: "ollama:north-mini-code-1.0",
        tools: [],
        store,
      });
      ```
    </CodeGroup>
  </Tab>
</Tabs>

<Note>
  For other store backends, including Redis and MongoDB, see the [store integrations](/oss/javascript/integrations/long-term-memory) list. For a MongoDB walkthrough, see [long-term memory with MongoDB](/oss/javascript/integrations/memory/mongodb-long-term-memory).
</Note>

Tools can then read from and write to the store using the `runtime.store` parameter. See [Read long-term memory in tools](#read-long-term-memory-in-tools) and [Write long-term memory from tools](#write-long-term-memory-from-tools) for examples.

<Tip>
  For a deeper dive into memory types (semantic, episodic, procedural) and strategies for writing memories, see the [Memory conceptual guide](/oss/javascript/concepts/memory#long-term-memory).
</Tip>

## Memory storage

LangGraph stores long-term memories as JSON documents in a [store](/oss/javascript/langgraph/stores).

Each memory is organized under a custom `namespace` (similar to a folder) and a distinct `key` (like a file name). Namespaces often include user or org IDs or other labels that makes it easier to organize information.

This structure enables hierarchical organization of memories. Cross-namespace searching is then supported through content filters.

<Tabs>
  <Tab title="InMemoryStore">
    ```ts theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    import { InMemoryStore } from "@langchain/langgraph";

    const embed = (texts: string[]): number[][] => {
      // Replace with an actual embedding function or LangChain embeddings object
      return texts.map(() => [1.0, 2.0]);
    };

    // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production use.
    const store = new InMemoryStore({ index: { embed, dims: 2 } });
    const userId = "my-user";
    const applicationContext = "chitchat";
    const namespace = [userId, applicationContext];

    await store.put(namespace, "a-memory", {
      rules: [
        "User likes short, direct language",
        "User only speaks English & TypeScript",
      ],
      "my-key": "my-value",
    });

    // get the "memory" by ID
    const item = await store.get(namespace, "a-memory");

    // search for "memories" within this namespace, filtering on content equivalence, sorted by vector similarity
    const items = await store.search(namespace, {
      filter: { "my-key": "my-value" },
      query: "language preferences",
    });
    ```
  </Tab>

  <Tab title="PostgreSQL">
    ```ts theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

    const embed = (texts: string[]): number[][] => {
      return texts.map(() => [1.0, 2.0]);
    };

    const DB_URI =
      process.env.POSTGRES_URI ??
      "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
    const store = PostgresStore.fromConnString(DB_URI, {
      index: { embed, dims: 2 },
    });
    await store.setup();

    const userId = "my-user";
    const applicationContext = "chitchat";
    const namespace = [userId, applicationContext];

    await store.put(namespace, "a-memory", {
      rules: [
        "User likes short, direct language",
        "User only speaks English & TypeScript",
      ],
      "my-key": "my-value",
    });

    const item = await store.get(namespace, "a-memory");
    const items = await store.search(namespace, {
      filter: { "my-key": "my-value" },
      query: "language preferences",
    });
    ```
  </Tab>
</Tabs>

For more information about the memory store, see the [Persistence](/oss/javascript/langgraph/stores) guide.

## Read long-term memory in tools

<Tabs>
  <Tab title="InMemoryStore">
    <CodeGroup>
      ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { createAgent, tool, type ToolRuntime } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production.
      const store = new InMemoryStore();
      const contextSchema = z.object({
        userId: z.string(),
      });

      // Write sample data to the store using the put method
      await store.put(
        ["users"], // Namespace to group related data together (users namespace for user data)
        "user_123", // Key within the namespace (user ID as key)
        {
          name: "John Smith",
          language: "English",
        }, // Data to store for the given user
      );

      const getUserInfo = tool(
        // Look up user info.
        async (_, runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>) => {
          // Access the store - same as that provided to `createAgent`
          const userId = runtime.context.userId;
          if (!userId) {
            throw new Error("userId is required");
          }
          // Retrieve data from store - returns StoreValue object with value and metadata
          const userInfo = await runtime.store.get(["users"], userId);
          return userInfo?.value ? JSON.stringify(userInfo.value) : "Unknown user";
        },
        {
          name: "getUserInfo",
          description: "Look up user info by userId from the store.",
          schema: z.object({}),
        },
      );

      const agent = createAgent({
        model: "google:gemini-3.6-flash",
        tools: [getUserInfo],
        contextSchema,
        // Pass store to agent - enables agent to access store when running tools
        store,
      });

      // Run the agent
      const result = await agent.invoke(
        { messages: [{ role: "user", content: "look up user information" }] },
        { context: { userId: "user_123" } },
      );

      console.log(result.messages.at(-1)?.content);

      /**
       * Outputs:
       * User Information:
       * - **Name:** John Smith
       * - **Language:** English
       */
      ```

      ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { createAgent, tool, type ToolRuntime } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production.
      const store = new InMemoryStore();
      const contextSchema = z.object({
        userId: z.string(),
      });

      // Write sample data to the store using the put method
      await store.put(
        ["users"], // Namespace to group related data together (users namespace for user data)
        "user_123", // Key within the namespace (user ID as key)
        {
          name: "John Smith",
          language: "English",
        }, // Data to store for the given user
      );

      const getUserInfo = tool(
        // Look up user info.
        async (_, runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>) => {
          // Access the store - same as that provided to `createAgent`
          const userId = runtime.context.userId;
          if (!userId) {
            throw new Error("userId is required");
          }
          // Retrieve data from store - returns StoreValue object with value and metadata
          const userInfo = await runtime.store.get(["users"], userId);
          return userInfo?.value ? JSON.stringify(userInfo.value) : "Unknown user";
        },
        {
          name: "getUserInfo",
          description: "Look up user info by userId from the store.",
          schema: z.object({}),
        },
      );

      const agent = createAgent({
        model: "openai:gpt-5.5",
        tools: [getUserInfo],
        contextSchema,
        // Pass store to agent - enables agent to access store when running tools
        store,
      });

      // Run the agent
      const result = await agent.invoke(
        { messages: [{ role: "user", content: "look up user information" }] },
        { context: { userId: "user_123" } },
      );

      console.log(result.messages.at(-1)?.content);

      /**
       * Outputs:
       * User Information:
       * - **Name:** John Smith
       * - **Language:** English
       */
      ```

      ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { createAgent, tool, type ToolRuntime } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production.
      const store = new InMemoryStore();
      const contextSchema = z.object({
        userId: z.string(),
      });

      // Write sample data to the store using the put method
      await store.put(
        ["users"], // Namespace to group related data together (users namespace for user data)
        "user_123", // Key within the namespace (user ID as key)
        {
          name: "John Smith",
          language: "English",
        }, // Data to store for the given user
      );

      const getUserInfo = tool(
        // Look up user info.
        async (_, runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>) => {
          // Access the store - same as that provided to `createAgent`
          const userId = runtime.context.userId;
          if (!userId) {
            throw new Error("userId is required");
          }
          // Retrieve data from store - returns StoreValue object with value and metadata
          const userInfo = await runtime.store.get(["users"], userId);
          return userInfo?.value ? JSON.stringify(userInfo.value) : "Unknown user";
        },
        {
          name: "getUserInfo",
          description: "Look up user info by userId from the store.",
          schema: z.object({}),
        },
      );

      const agent = createAgent({
        model: "anthropic:claude-sonnet-5",
        tools: [getUserInfo],
        contextSchema,
        // Pass store to agent - enables agent to access store when running tools
        store,
      });

      // Run the agent
      const result = await agent.invoke(
        { messages: [{ role: "user", content: "look up user information" }] },
        { context: { userId: "user_123" } },
      );

      console.log(result.messages.at(-1)?.content);

      /**
       * Outputs:
       * User Information:
       * - **Name:** John Smith
       * - **Language:** English
       */
      ```

      ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { createAgent, tool, type ToolRuntime } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production.
      const store = new InMemoryStore();
      const contextSchema = z.object({
        userId: z.string(),
      });

      // Write sample data to the store using the put method
      await store.put(
        ["users"], // Namespace to group related data together (users namespace for user data)
        "user_123", // Key within the namespace (user ID as key)
        {
          name: "John Smith",
          language: "English",
        }, // Data to store for the given user
      );

      const getUserInfo = tool(
        // Look up user info.
        async (_, runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>) => {
          // Access the store - same as that provided to `createAgent`
          const userId = runtime.context.userId;
          if (!userId) {
            throw new Error("userId is required");
          }
          // Retrieve data from store - returns StoreValue object with value and metadata
          const userInfo = await runtime.store.get(["users"], userId);
          return userInfo?.value ? JSON.stringify(userInfo.value) : "Unknown user";
        },
        {
          name: "getUserInfo",
          description: "Look up user info by userId from the store.",
          schema: z.object({}),
        },
      );

      const agent = createAgent({
        model: "openrouter:z-ai/glm-5.2",
        tools: [getUserInfo],
        contextSchema,
        // Pass store to agent - enables agent to access store when running tools
        store,
      });

      // Run the agent
      const result = await agent.invoke(
        { messages: [{ role: "user", content: "look up user information" }] },
        { context: { userId: "user_123" } },
      );

      console.log(result.messages.at(-1)?.content);

      /**
       * Outputs:
       * User Information:
       * - **Name:** John Smith
       * - **Language:** English
       */
      ```

      ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { createAgent, tool, type ToolRuntime } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production.
      const store = new InMemoryStore();
      const contextSchema = z.object({
        userId: z.string(),
      });

      // Write sample data to the store using the put method
      await store.put(
        ["users"], // Namespace to group related data together (users namespace for user data)
        "user_123", // Key within the namespace (user ID as key)
        {
          name: "John Smith",
          language: "English",
        }, // Data to store for the given user
      );

      const getUserInfo = tool(
        // Look up user info.
        async (_, runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>) => {
          // Access the store - same as that provided to `createAgent`
          const userId = runtime.context.userId;
          if (!userId) {
            throw new Error("userId is required");
          }
          // Retrieve data from store - returns StoreValue object with value and metadata
          const userInfo = await runtime.store.get(["users"], userId);
          return userInfo?.value ? JSON.stringify(userInfo.value) : "Unknown user";
        },
        {
          name: "getUserInfo",
          description: "Look up user info by userId from the store.",
          schema: z.object({}),
        },
      );

      const agent = createAgent({
        model: "fireworks:accounts/fireworks/models/glm-5p2",
        tools: [getUserInfo],
        contextSchema,
        // Pass store to agent - enables agent to access store when running tools
        store,
      });

      // Run the agent
      const result = await agent.invoke(
        { messages: [{ role: "user", content: "look up user information" }] },
        { context: { userId: "user_123" } },
      );

      console.log(result.messages.at(-1)?.content);

      /**
       * Outputs:
       * User Information:
       * - **Name:** John Smith
       * - **Language:** English
       */
      ```

      ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { createAgent, tool, type ToolRuntime } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production.
      const store = new InMemoryStore();
      const contextSchema = z.object({
        userId: z.string(),
      });

      // Write sample data to the store using the put method
      await store.put(
        ["users"], // Namespace to group related data together (users namespace for user data)
        "user_123", // Key within the namespace (user ID as key)
        {
          name: "John Smith",
          language: "English",
        }, // Data to store for the given user
      );

      const getUserInfo = tool(
        // Look up user info.
        async (_, runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>) => {
          // Access the store - same as that provided to `createAgent`
          const userId = runtime.context.userId;
          if (!userId) {
            throw new Error("userId is required");
          }
          // Retrieve data from store - returns StoreValue object with value and metadata
          const userInfo = await runtime.store.get(["users"], userId);
          return userInfo?.value ? JSON.stringify(userInfo.value) : "Unknown user";
        },
        {
          name: "getUserInfo",
          description: "Look up user info by userId from the store.",
          schema: z.object({}),
        },
      );

      const agent = createAgent({
        model: "baseten:zai-org/GLM-5.2",
        tools: [getUserInfo],
        contextSchema,
        // Pass store to agent - enables agent to access store when running tools
        store,
      });

      // Run the agent
      const result = await agent.invoke(
        { messages: [{ role: "user", content: "look up user information" }] },
        { context: { userId: "user_123" } },
      );

      console.log(result.messages.at(-1)?.content);

      /**
       * Outputs:
       * User Information:
       * - **Name:** John Smith
       * - **Language:** English
       */
      ```

      ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { createAgent, tool, type ToolRuntime } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production.
      const store = new InMemoryStore();
      const contextSchema = z.object({
        userId: z.string(),
      });

      // Write sample data to the store using the put method
      await store.put(
        ["users"], // Namespace to group related data together (users namespace for user data)
        "user_123", // Key within the namespace (user ID as key)
        {
          name: "John Smith",
          language: "English",
        }, // Data to store for the given user
      );

      const getUserInfo = tool(
        // Look up user info.
        async (_, runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>) => {
          // Access the store - same as that provided to `createAgent`
          const userId = runtime.context.userId;
          if (!userId) {
            throw new Error("userId is required");
          }
          // Retrieve data from store - returns StoreValue object with value and metadata
          const userInfo = await runtime.store.get(["users"], userId);
          return userInfo?.value ? JSON.stringify(userInfo.value) : "Unknown user";
        },
        {
          name: "getUserInfo",
          description: "Look up user info by userId from the store.",
          schema: z.object({}),
        },
      );

      const agent = createAgent({
        model: "ollama:north-mini-code-1.0",
        tools: [getUserInfo],
        contextSchema,
        // Pass store to agent - enables agent to access store when running tools
        store,
      });

      // Run the agent
      const result = await agent.invoke(
        { messages: [{ role: "user", content: "look up user information" }] },
        { context: { userId: "user_123" } },
      );

      console.log(result.messages.at(-1)?.content);

      /**
       * Outputs:
       * User Information:
       * - **Name:** John Smith
       * - **Language:** English
       */
      ```
    </CodeGroup>

    <Card title="View example trace" icon="chart-line" href="https://smith.langchain.com/public/402f8832-35d4-4c95-9ebd-cb371af7366f/r" arrow horizontal>
      Open a public LangSmith run for this example.
    </Card>
  </Tab>

  <Tab title="PostgreSQL">
    <CodeGroup>
      ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { createAgent, tool, type ToolRuntime } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const contextSchema = z.object({ userId: z.string() });

      await store.put(["users"], "user_123", {
        name: "John Smith",
        language: "English",
      });

      const getUserInfo = tool(
        async (_, runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>) => {
          const userId = runtime.context.userId;
          if (!userId) throw new Error("userId is required");
          const userInfo = await runtime.store.get(["users"], userId);
          return userInfo?.value ? JSON.stringify(userInfo.value) : "Unknown user";
        },
        {
          name: "getUserInfo",
          description: "Look up user info by userId from the store.",
          schema: z.object({}),
        },
      );

      const agent = createAgent({
        model: "google:gemini-3.6-flash",
        tools: [getUserInfo],
        contextSchema,
        store,
      });

      await agent.invoke(
        { messages: [{ role: "user", content: "look up user information" }] },
        { context: { userId: "user_123" } },
      );
      ```

      ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { createAgent, tool, type ToolRuntime } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const contextSchema = z.object({ userId: z.string() });

      await store.put(["users"], "user_123", {
        name: "John Smith",
        language: "English",
      });

      const getUserInfo = tool(
        async (_, runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>) => {
          const userId = runtime.context.userId;
          if (!userId) throw new Error("userId is required");
          const userInfo = await runtime.store.get(["users"], userId);
          return userInfo?.value ? JSON.stringify(userInfo.value) : "Unknown user";
        },
        {
          name: "getUserInfo",
          description: "Look up user info by userId from the store.",
          schema: z.object({}),
        },
      );

      const agent = createAgent({
        model: "openai:gpt-5.5",
        tools: [getUserInfo],
        contextSchema,
        store,
      });

      await agent.invoke(
        { messages: [{ role: "user", content: "look up user information" }] },
        { context: { userId: "user_123" } },
      );
      ```

      ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { createAgent, tool, type ToolRuntime } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const contextSchema = z.object({ userId: z.string() });

      await store.put(["users"], "user_123", {
        name: "John Smith",
        language: "English",
      });

      const getUserInfo = tool(
        async (_, runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>) => {
          const userId = runtime.context.userId;
          if (!userId) throw new Error("userId is required");
          const userInfo = await runtime.store.get(["users"], userId);
          return userInfo?.value ? JSON.stringify(userInfo.value) : "Unknown user";
        },
        {
          name: "getUserInfo",
          description: "Look up user info by userId from the store.",
          schema: z.object({}),
        },
      );

      const agent = createAgent({
        model: "anthropic:claude-sonnet-5",
        tools: [getUserInfo],
        contextSchema,
        store,
      });

      await agent.invoke(
        { messages: [{ role: "user", content: "look up user information" }] },
        { context: { userId: "user_123" } },
      );
      ```

      ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { createAgent, tool, type ToolRuntime } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const contextSchema = z.object({ userId: z.string() });

      await store.put(["users"], "user_123", {
        name: "John Smith",
        language: "English",
      });

      const getUserInfo = tool(
        async (_, runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>) => {
          const userId = runtime.context.userId;
          if (!userId) throw new Error("userId is required");
          const userInfo = await runtime.store.get(["users"], userId);
          return userInfo?.value ? JSON.stringify(userInfo.value) : "Unknown user";
        },
        {
          name: "getUserInfo",
          description: "Look up user info by userId from the store.",
          schema: z.object({}),
        },
      );

      const agent = createAgent({
        model: "openrouter:z-ai/glm-5.2",
        tools: [getUserInfo],
        contextSchema,
        store,
      });

      await agent.invoke(
        { messages: [{ role: "user", content: "look up user information" }] },
        { context: { userId: "user_123" } },
      );
      ```

      ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { createAgent, tool, type ToolRuntime } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const contextSchema = z.object({ userId: z.string() });

      await store.put(["users"], "user_123", {
        name: "John Smith",
        language: "English",
      });

      const getUserInfo = tool(
        async (_, runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>) => {
          const userId = runtime.context.userId;
          if (!userId) throw new Error("userId is required");
          const userInfo = await runtime.store.get(["users"], userId);
          return userInfo?.value ? JSON.stringify(userInfo.value) : "Unknown user";
        },
        {
          name: "getUserInfo",
          description: "Look up user info by userId from the store.",
          schema: z.object({}),
        },
      );

      const agent = createAgent({
        model: "fireworks:accounts/fireworks/models/glm-5p2",
        tools: [getUserInfo],
        contextSchema,
        store,
      });

      await agent.invoke(
        { messages: [{ role: "user", content: "look up user information" }] },
        { context: { userId: "user_123" } },
      );
      ```

      ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { createAgent, tool, type ToolRuntime } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const contextSchema = z.object({ userId: z.string() });

      await store.put(["users"], "user_123", {
        name: "John Smith",
        language: "English",
      });

      const getUserInfo = tool(
        async (_, runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>) => {
          const userId = runtime.context.userId;
          if (!userId) throw new Error("userId is required");
          const userInfo = await runtime.store.get(["users"], userId);
          return userInfo?.value ? JSON.stringify(userInfo.value) : "Unknown user";
        },
        {
          name: "getUserInfo",
          description: "Look up user info by userId from the store.",
          schema: z.object({}),
        },
      );

      const agent = createAgent({
        model: "baseten:zai-org/GLM-5.2",
        tools: [getUserInfo],
        contextSchema,
        store,
      });

      await agent.invoke(
        { messages: [{ role: "user", content: "look up user information" }] },
        { context: { userId: "user_123" } },
      );
      ```

      ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { createAgent, tool, type ToolRuntime } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const contextSchema = z.object({ userId: z.string() });

      await store.put(["users"], "user_123", {
        name: "John Smith",
        language: "English",
      });

      const getUserInfo = tool(
        async (_, runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>) => {
          const userId = runtime.context.userId;
          if (!userId) throw new Error("userId is required");
          const userInfo = await runtime.store.get(["users"], userId);
          return userInfo?.value ? JSON.stringify(userInfo.value) : "Unknown user";
        },
        {
          name: "getUserInfo",
          description: "Look up user info by userId from the store.",
          schema: z.object({}),
        },
      );

      const agent = createAgent({
        model: "ollama:north-mini-code-1.0",
        tools: [getUserInfo],
        contextSchema,
        store,
      });

      await agent.invoke(
        { messages: [{ role: "user", content: "look up user information" }] },
        { context: { userId: "user_123" } },
      );
      ```
    </CodeGroup>

    <Card title="View example trace" icon="chart-line" href="https://smith.langchain.com/public/3cac0150-fe8c-4346-904f-a67a8d6fb156/r" arrow horizontal>
      Open a public LangSmith run for this example.
    </Card>
  </Tab>
</Tabs>

<a id="write-long-term" />

## Write long-term memory from tools

<Tabs>
  <Tab title="InMemoryStore">
    <CodeGroup>
      ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { tool, createAgent, type ToolRuntime } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production.
      const store = new InMemoryStore();

      const contextSchema = z.object({
        userId: z.string(),
      });

      // Schema defines the structure of user information for the LLM
      const UserInfo = z.object({
        name: z.string(),
      });

      // Tool that allows agent to update user information (useful for chat applications)
      const saveUserInfo = tool(
        async (
          userInfo: z.infer<typeof UserInfo>,
          runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>,
        ) => {
          const userId = runtime.context.userId;
          if (!userId) {
            throw new Error("userId is required");
          }
          // Store data in the store (namespace, key, data)
          await runtime.store.put(["users"], userId, userInfo);
          return "Successfully saved user info.";
        },
        {
          name: "save_user_info",
          description: "Save user info",
          schema: UserInfo,
        },
      );

      const agent = createAgent({
        model: "google:gemini-3.6-flash",
        tools: [saveUserInfo],
        contextSchema,
        store,
      });

      // Run the agent
      await agent.invoke(
        { messages: [{ role: "user", content: "My name is John Smith" }] },
        // userId passed in context to identify whose information is being updated
        { context: { userId: "user_123" } },
      );

      // You can access the store directly to get the value
      const result = await store.get(["users"], "user_123");
      console.log(result?.value); // Output: { name: "John Smith" }
      ```

      ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { tool, createAgent, type ToolRuntime } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production.
      const store = new InMemoryStore();

      const contextSchema = z.object({
        userId: z.string(),
      });

      // Schema defines the structure of user information for the LLM
      const UserInfo = z.object({
        name: z.string(),
      });

      // Tool that allows agent to update user information (useful for chat applications)
      const saveUserInfo = tool(
        async (
          userInfo: z.infer<typeof UserInfo>,
          runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>,
        ) => {
          const userId = runtime.context.userId;
          if (!userId) {
            throw new Error("userId is required");
          }
          // Store data in the store (namespace, key, data)
          await runtime.store.put(["users"], userId, userInfo);
          return "Successfully saved user info.";
        },
        {
          name: "save_user_info",
          description: "Save user info",
          schema: UserInfo,
        },
      );

      const agent = createAgent({
        model: "openai:gpt-5.5",
        tools: [saveUserInfo],
        contextSchema,
        store,
      });

      // Run the agent
      await agent.invoke(
        { messages: [{ role: "user", content: "My name is John Smith" }] },
        // userId passed in context to identify whose information is being updated
        { context: { userId: "user_123" } },
      );

      // You can access the store directly to get the value
      const result = await store.get(["users"], "user_123");
      console.log(result?.value); // Output: { name: "John Smith" }
      ```

      ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { tool, createAgent, type ToolRuntime } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production.
      const store = new InMemoryStore();

      const contextSchema = z.object({
        userId: z.string(),
      });

      // Schema defines the structure of user information for the LLM
      const UserInfo = z.object({
        name: z.string(),
      });

      // Tool that allows agent to update user information (useful for chat applications)
      const saveUserInfo = tool(
        async (
          userInfo: z.infer<typeof UserInfo>,
          runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>,
        ) => {
          const userId = runtime.context.userId;
          if (!userId) {
            throw new Error("userId is required");
          }
          // Store data in the store (namespace, key, data)
          await runtime.store.put(["users"], userId, userInfo);
          return "Successfully saved user info.";
        },
        {
          name: "save_user_info",
          description: "Save user info",
          schema: UserInfo,
        },
      );

      const agent = createAgent({
        model: "anthropic:claude-sonnet-5",
        tools: [saveUserInfo],
        contextSchema,
        store,
      });

      // Run the agent
      await agent.invoke(
        { messages: [{ role: "user", content: "My name is John Smith" }] },
        // userId passed in context to identify whose information is being updated
        { context: { userId: "user_123" } },
      );

      // You can access the store directly to get the value
      const result = await store.get(["users"], "user_123");
      console.log(result?.value); // Output: { name: "John Smith" }
      ```

      ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { tool, createAgent, type ToolRuntime } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production.
      const store = new InMemoryStore();

      const contextSchema = z.object({
        userId: z.string(),
      });

      // Schema defines the structure of user information for the LLM
      const UserInfo = z.object({
        name: z.string(),
      });

      // Tool that allows agent to update user information (useful for chat applications)
      const saveUserInfo = tool(
        async (
          userInfo: z.infer<typeof UserInfo>,
          runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>,
        ) => {
          const userId = runtime.context.userId;
          if (!userId) {
            throw new Error("userId is required");
          }
          // Store data in the store (namespace, key, data)
          await runtime.store.put(["users"], userId, userInfo);
          return "Successfully saved user info.";
        },
        {
          name: "save_user_info",
          description: "Save user info",
          schema: UserInfo,
        },
      );

      const agent = createAgent({
        model: "openrouter:z-ai/glm-5.2",
        tools: [saveUserInfo],
        contextSchema,
        store,
      });

      // Run the agent
      await agent.invoke(
        { messages: [{ role: "user", content: "My name is John Smith" }] },
        // userId passed in context to identify whose information is being updated
        { context: { userId: "user_123" } },
      );

      // You can access the store directly to get the value
      const result = await store.get(["users"], "user_123");
      console.log(result?.value); // Output: { name: "John Smith" }
      ```

      ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { tool, createAgent, type ToolRuntime } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production.
      const store = new InMemoryStore();

      const contextSchema = z.object({
        userId: z.string(),
      });

      // Schema defines the structure of user information for the LLM
      const UserInfo = z.object({
        name: z.string(),
      });

      // Tool that allows agent to update user information (useful for chat applications)
      const saveUserInfo = tool(
        async (
          userInfo: z.infer<typeof UserInfo>,
          runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>,
        ) => {
          const userId = runtime.context.userId;
          if (!userId) {
            throw new Error("userId is required");
          }
          // Store data in the store (namespace, key, data)
          await runtime.store.put(["users"], userId, userInfo);
          return "Successfully saved user info.";
        },
        {
          name: "save_user_info",
          description: "Save user info",
          schema: UserInfo,
        },
      );

      const agent = createAgent({
        model: "fireworks:accounts/fireworks/models/glm-5p2",
        tools: [saveUserInfo],
        contextSchema,
        store,
      });

      // Run the agent
      await agent.invoke(
        { messages: [{ role: "user", content: "My name is John Smith" }] },
        // userId passed in context to identify whose information is being updated
        { context: { userId: "user_123" } },
      );

      // You can access the store directly to get the value
      const result = await store.get(["users"], "user_123");
      console.log(result?.value); // Output: { name: "John Smith" }
      ```

      ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { tool, createAgent, type ToolRuntime } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production.
      const store = new InMemoryStore();

      const contextSchema = z.object({
        userId: z.string(),
      });

      // Schema defines the structure of user information for the LLM
      const UserInfo = z.object({
        name: z.string(),
      });

      // Tool that allows agent to update user information (useful for chat applications)
      const saveUserInfo = tool(
        async (
          userInfo: z.infer<typeof UserInfo>,
          runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>,
        ) => {
          const userId = runtime.context.userId;
          if (!userId) {
            throw new Error("userId is required");
          }
          // Store data in the store (namespace, key, data)
          await runtime.store.put(["users"], userId, userInfo);
          return "Successfully saved user info.";
        },
        {
          name: "save_user_info",
          description: "Save user info",
          schema: UserInfo,
        },
      );

      const agent = createAgent({
        model: "baseten:zai-org/GLM-5.2",
        tools: [saveUserInfo],
        contextSchema,
        store,
      });

      // Run the agent
      await agent.invoke(
        { messages: [{ role: "user", content: "My name is John Smith" }] },
        // userId passed in context to identify whose information is being updated
        { context: { userId: "user_123" } },
      );

      // You can access the store directly to get the value
      const result = await store.get(["users"], "user_123");
      console.log(result?.value); // Output: { name: "John Smith" }
      ```

      ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { tool, createAgent, type ToolRuntime } from "langchain";
      import { InMemoryStore } from "@langchain/langgraph";

      // InMemoryStore saves data to an in-memory dictionary. Use a DB-backed store in production.
      const store = new InMemoryStore();

      const contextSchema = z.object({
        userId: z.string(),
      });

      // Schema defines the structure of user information for the LLM
      const UserInfo = z.object({
        name: z.string(),
      });

      // Tool that allows agent to update user information (useful for chat applications)
      const saveUserInfo = tool(
        async (
          userInfo: z.infer<typeof UserInfo>,
          runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>,
        ) => {
          const userId = runtime.context.userId;
          if (!userId) {
            throw new Error("userId is required");
          }
          // Store data in the store (namespace, key, data)
          await runtime.store.put(["users"], userId, userInfo);
          return "Successfully saved user info.";
        },
        {
          name: "save_user_info",
          description: "Save user info",
          schema: UserInfo,
        },
      );

      const agent = createAgent({
        model: "ollama:north-mini-code-1.0",
        tools: [saveUserInfo],
        contextSchema,
        store,
      });

      // Run the agent
      await agent.invoke(
        { messages: [{ role: "user", content: "My name is John Smith" }] },
        // userId passed in context to identify whose information is being updated
        { context: { userId: "user_123" } },
      );

      // You can access the store directly to get the value
      const result = await store.get(["users"], "user_123");
      console.log(result?.value); // Output: { name: "John Smith" }
      ```
    </CodeGroup>

    <Card title="View example trace" icon="chart-line" href="https://smith.langchain.com/public/1329ec1b-63c9-4cea-99be-74a763a4cc16/r" arrow horizontal>
      Open a public LangSmith run for this example.
    </Card>
  </Tab>

  <Tab title="PostgreSQL">
    <CodeGroup>
      ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { tool, createAgent, type ToolRuntime } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const contextSchema = z.object({ userId: z.string() });

      const UserInfo = z.object({ name: z.string() });

      const saveUserInfo = tool(
        async (
          userInfo: z.infer<typeof UserInfo>,
          runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>,
        ) => {
          const userId = runtime.context.userId;
          if (!userId) throw new Error("userId is required");
          await runtime.store.put(["users"], userId, userInfo);
          return "Successfully saved user info.";
        },
        { name: "save_user_info", description: "Save user info", schema: UserInfo },
      );

      const agent = createAgent({
        model: "google:gemini-3.6-flash",
        tools: [saveUserInfo],
        contextSchema,
        store,
      });

      await agent.invoke(
        { messages: [{ role: "user", content: "My name is John Smith" }] },
        { context: { userId: "user_123" } },
      );

      const result = await store.get(["users"], "user_123");
      console.log(result?.value);
      ```

      ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { tool, createAgent, type ToolRuntime } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const contextSchema = z.object({ userId: z.string() });

      const UserInfo = z.object({ name: z.string() });

      const saveUserInfo = tool(
        async (
          userInfo: z.infer<typeof UserInfo>,
          runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>,
        ) => {
          const userId = runtime.context.userId;
          if (!userId) throw new Error("userId is required");
          await runtime.store.put(["users"], userId, userInfo);
          return "Successfully saved user info.";
        },
        { name: "save_user_info", description: "Save user info", schema: UserInfo },
      );

      const agent = createAgent({
        model: "openai:gpt-5.5",
        tools: [saveUserInfo],
        contextSchema,
        store,
      });

      await agent.invoke(
        { messages: [{ role: "user", content: "My name is John Smith" }] },
        { context: { userId: "user_123" } },
      );

      const result = await store.get(["users"], "user_123");
      console.log(result?.value);
      ```

      ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { tool, createAgent, type ToolRuntime } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const contextSchema = z.object({ userId: z.string() });

      const UserInfo = z.object({ name: z.string() });

      const saveUserInfo = tool(
        async (
          userInfo: z.infer<typeof UserInfo>,
          runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>,
        ) => {
          const userId = runtime.context.userId;
          if (!userId) throw new Error("userId is required");
          await runtime.store.put(["users"], userId, userInfo);
          return "Successfully saved user info.";
        },
        { name: "save_user_info", description: "Save user info", schema: UserInfo },
      );

      const agent = createAgent({
        model: "anthropic:claude-sonnet-5",
        tools: [saveUserInfo],
        contextSchema,
        store,
      });

      await agent.invoke(
        { messages: [{ role: "user", content: "My name is John Smith" }] },
        { context: { userId: "user_123" } },
      );

      const result = await store.get(["users"], "user_123");
      console.log(result?.value);
      ```

      ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { tool, createAgent, type ToolRuntime } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const contextSchema = z.object({ userId: z.string() });

      const UserInfo = z.object({ name: z.string() });

      const saveUserInfo = tool(
        async (
          userInfo: z.infer<typeof UserInfo>,
          runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>,
        ) => {
          const userId = runtime.context.userId;
          if (!userId) throw new Error("userId is required");
          await runtime.store.put(["users"], userId, userInfo);
          return "Successfully saved user info.";
        },
        { name: "save_user_info", description: "Save user info", schema: UserInfo },
      );

      const agent = createAgent({
        model: "openrouter:z-ai/glm-5.2",
        tools: [saveUserInfo],
        contextSchema,
        store,
      });

      await agent.invoke(
        { messages: [{ role: "user", content: "My name is John Smith" }] },
        { context: { userId: "user_123" } },
      );

      const result = await store.get(["users"], "user_123");
      console.log(result?.value);
      ```

      ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { tool, createAgent, type ToolRuntime } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const contextSchema = z.object({ userId: z.string() });

      const UserInfo = z.object({ name: z.string() });

      const saveUserInfo = tool(
        async (
          userInfo: z.infer<typeof UserInfo>,
          runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>,
        ) => {
          const userId = runtime.context.userId;
          if (!userId) throw new Error("userId is required");
          await runtime.store.put(["users"], userId, userInfo);
          return "Successfully saved user info.";
        },
        { name: "save_user_info", description: "Save user info", schema: UserInfo },
      );

      const agent = createAgent({
        model: "fireworks:accounts/fireworks/models/glm-5p2",
        tools: [saveUserInfo],
        contextSchema,
        store,
      });

      await agent.invoke(
        { messages: [{ role: "user", content: "My name is John Smith" }] },
        { context: { userId: "user_123" } },
      );

      const result = await store.get(["users"], "user_123");
      console.log(result?.value);
      ```

      ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { tool, createAgent, type ToolRuntime } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const contextSchema = z.object({ userId: z.string() });

      const UserInfo = z.object({ name: z.string() });

      const saveUserInfo = tool(
        async (
          userInfo: z.infer<typeof UserInfo>,
          runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>,
        ) => {
          const userId = runtime.context.userId;
          if (!userId) throw new Error("userId is required");
          await runtime.store.put(["users"], userId, userInfo);
          return "Successfully saved user info.";
        },
        { name: "save_user_info", description: "Save user info", schema: UserInfo },
      );

      const agent = createAgent({
        model: "baseten:zai-org/GLM-5.2",
        tools: [saveUserInfo],
        contextSchema,
        store,
      });

      await agent.invoke(
        { messages: [{ role: "user", content: "My name is John Smith" }] },
        { context: { userId: "user_123" } },
      );

      const result = await store.get(["users"], "user_123");
      console.log(result?.value);
      ```

      ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      import * as z from "zod";
      import { tool, createAgent, type ToolRuntime } from "langchain";
      import { PostgresStore } from "@langchain/langgraph-checkpoint-postgres/store";

      const DB_URI =
        process.env.POSTGRES_URI ??
        "postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable";
      const store = PostgresStore.fromConnString(DB_URI);
      await store.setup();

      const contextSchema = z.object({ userId: z.string() });

      const UserInfo = z.object({ name: z.string() });

      const saveUserInfo = tool(
        async (
          userInfo: z.infer<typeof UserInfo>,
          runtime: ToolRuntime<unknown, z.infer<typeof contextSchema>>,
        ) => {
          const userId = runtime.context.userId;
          if (!userId) throw new Error("userId is required");
          await runtime.store.put(["users"], userId, userInfo);
          return "Successfully saved user info.";
        },
        { name: "save_user_info", description: "Save user info", schema: UserInfo },
      );

      const agent = createAgent({
        model: "ollama:north-mini-code-1.0",
        tools: [saveUserInfo],
        contextSchema,
        store,
      });

      await agent.invoke(
        { messages: [{ role: "user", content: "My name is John Smith" }] },
        { context: { userId: "user_123" } },
      );

      const result = await store.get(["users"], "user_123");
      console.log(result?.value);
      ```
    </CodeGroup>

    <Card title="View example trace" icon="chart-line" href="https://smith.langchain.com/public/85c902fd-dbd7-4d73-9d11-a09f01dace8f/r" arrow horizontal>
      Open a public LangSmith run for this example.
    </Card>
  </Tab>
</Tabs>

***

<div className="source-links">
  <Callout icon="terminal-2">
    [Connect these docs](/use-these-docs) to your agent of choice via MCP for real-time answers.
  </Callout>

  <Callout icon="edit">
    [Edit this page on GitHub](https://github.com/langchain-ai/docs/edit/main/src/oss/langchain/long-term-memory.mdx) or [file an issue](https://github.com/langchain-ai/docs/issues/new/choose).
  </Callout>
</div>
