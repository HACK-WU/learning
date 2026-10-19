> ## Documentation Index
> Fetch the complete documentation index at: https://docs.langchain.com/llms.txt
> Use this file to discover all available pages before exploring further.

# Streaming

> Stream real-time updates from agent runs

<Tip>
  For new applications, we recommend [event streaming](/oss/javascript/langchain/event-streaming)—the typed-projection API introduced in LangChain v1.3. Event streaming gives you separate iterators per projection (messages, values, tool calls, subgraphs) so you can consume them independently instead of branching on `stream_mode` chunks.
</Tip>

LangChain implements a streaming system to surface real-time updates.

Streaming is crucial for enhancing the responsiveness of applications built on LLMs. By displaying output progressively, even before a complete response is ready, streaming significantly improves user experience (UX), particularly when dealing with the latency of LLMs.

## Overview

LangChain's streaming system lets you surface live feedback from agent runs to your application.

What's possible with LangChain streaming:

* <Icon icon="brain" size={16} /> [**Stream agent progress**](#agent-progress)—get state updates after each agent step.
* <Icon icon="binary" size={16} /> [**Stream LLM tokens**](#llm-tokens)—stream language model tokens as they're generated.
* <Icon icon="bulb" size={16} /> [**Stream thinking / reasoning tokens**](#streaming-thinking-/-reasoning-tokens)—surface model reasoning as it's generated.
* <Icon icon="table" size={16} /> [**Stream custom updates**](#custom-updates)—emit user-defined signals (e.g., `"Fetched 10/100 records"`).
* <Icon icon="stack-push" size={16} /> [**Stream multiple modes**](#stream-multiple-modes)—choose from `updates` (agent progress), `messages` (LLM tokens + metadata), or `custom` (arbitrary user data).

See the [common patterns](#common-patterns) section below for additional end-to-end examples.

## Supported stream modes

Pass one or more of the following stream modes as a list to the [`stream`](https://reference.langchain.com/javascript/classes/_langchain_langgraph.index.CompiledStateGraph.html#stream) method:

| Mode | Description |
| - | - |
| `updates` | Streams state updates after each agent step. If multiple updates are made in the same step (e.g., multiple nodes are run), those updates are streamed separately. |
| `messages` | Streams tuples of `(token, metadata)` from any graph nodes where an LLM is invoked. |
| `custom` | Streams custom data from inside your graph nodes using the stream writer. |

## Agent progress

To stream agent progress, use the [`stream`](https://reference.langchain.com/javascript/classes/_langchain_langgraph.index.CompiledStateGraph.html#stream) method with `streamMode: "updates"`. This emits an event after every agent step.

For example, if you have an agent that calls a tool once, you should see the following updates:

* **LLM node**: [`AIMessage`](https://reference.langchain.com/javascript/langchain-core/messages/AIMessage) with tool call requests
* **Tool node**: [`ToolMessage`](https://reference.langchain.com/javascript/langchain-core/messages/ToolMessage) with execution result
* **LLM node**: Final AI response

Pass a `thread_id` via `configurable` so the conversation is checkpointed and follow-up turns can resume the same history. `thread_id` is independent of `streamMode`; you can also pass `context` alongside it for per-run data your tools read from `runtime.context`.

<CodeGroup>
  ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, tool } from "langchain";
  import { uuid7 } from "langsmith";
  import { MemorySaver } from "@langchain/langgraph";
  import z from "zod";

  const getWeather = tool(
    async ({ city }) => {
      return `The weather in ${city} is always sunny!`;
    },
    {
      name: "get_weather",
      description: "Get weather for a given city.",
      schema: z.object({
        city: z.string(),
      }),
    },
  );

  const agent = createAgent({
    model: "google:gemini-3.6-flash",
    tools: [getWeather],
    checkpointer: new MemorySaver(),
  });

  const config = { configurable: { thread_id: uuid7() } };

  const stream = await agent.streamEvents(
    { messages: [{ role: "user", content: "what is the weather in sf" }] },
    { ...config, version: "v3" },
  );
  await Promise.all([
    (async () => {
      for await (const message of stream.messages) {
        for await (const token of message.text) {
          process.stdout.write(token);
        }
      }
    })(),
    (async () => {
      for await (const call of stream.toolCalls) {
        console.log(`\nTool call: ${call.name}(${JSON.stringify(call.input)})`);
        console.log(`Tool result: ${await call.output}`);
      }
    })(),
  ]);

  const finalState = await stream.output;
  // Tool call: get_weather({"city":"San Francisco"})
  // Tool result: [object ToolMessage]
  // According to the data I have, the weather in San Francisco is always sunny! Would you like current conditions or a short forecast for today or the next few days?
  ```

  ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, tool } from "langchain";
  import { uuid7 } from "langsmith";
  import { MemorySaver } from "@langchain/langgraph";
  import z from "zod";

  const getWeather = tool(
    async ({ city }) => {
      return `The weather in ${city} is always sunny!`;
    },
    {
      name: "get_weather",
      description: "Get weather for a given city.",
      schema: z.object({
        city: z.string(),
      }),
    },
  );

  const agent = createAgent({
    model: "openai:gpt-5.5",
    tools: [getWeather],
    checkpointer: new MemorySaver(),
  });

  const config = { configurable: { thread_id: uuid7() } };

  const stream = await agent.streamEvents(
    { messages: [{ role: "user", content: "what is the weather in sf" }] },
    { ...config, version: "v3" },
  );
  await Promise.all([
    (async () => {
      for await (const message of stream.messages) {
        for await (const token of message.text) {
          process.stdout.write(token);
        }
      }
    })(),
    (async () => {
      for await (const call of stream.toolCalls) {
        console.log(`\nTool call: ${call.name}(${JSON.stringify(call.input)})`);
        console.log(`Tool result: ${await call.output}`);
      }
    })(),
  ]);

  const finalState = await stream.output;
  // Tool call: get_weather({"city":"San Francisco"})
  // Tool result: [object ToolMessage]
  // According to the data I have, the weather in San Francisco is always sunny! Would you like current conditions or a short forecast for today or the next few days?
  ```

  ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, tool } from "langchain";
  import { uuid7 } from "langsmith";
  import { MemorySaver } from "@langchain/langgraph";
  import z from "zod";

  const getWeather = tool(
    async ({ city }) => {
      return `The weather in ${city} is always sunny!`;
    },
    {
      name: "get_weather",
      description: "Get weather for a given city.",
      schema: z.object({
        city: z.string(),
      }),
    },
  );

  const agent = createAgent({
    model: "anthropic:claude-sonnet-5",
    tools: [getWeather],
    checkpointer: new MemorySaver(),
  });

  const config = { configurable: { thread_id: uuid7() } };

  const stream = await agent.streamEvents(
    { messages: [{ role: "user", content: "what is the weather in sf" }] },
    { ...config, version: "v3" },
  );
  await Promise.all([
    (async () => {
      for await (const message of stream.messages) {
        for await (const token of message.text) {
          process.stdout.write(token);
        }
      }
    })(),
    (async () => {
      for await (const call of stream.toolCalls) {
        console.log(`\nTool call: ${call.name}(${JSON.stringify(call.input)})`);
        console.log(`Tool result: ${await call.output}`);
      }
    })(),
  ]);

  const finalState = await stream.output;
  // Tool call: get_weather({"city":"San Francisco"})
  // Tool result: [object ToolMessage]
  // According to the data I have, the weather in San Francisco is always sunny! Would you like current conditions or a short forecast for today or the next few days?
  ```

  ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, tool } from "langchain";
  import { uuid7 } from "langsmith";
  import { MemorySaver } from "@langchain/langgraph";
  import z from "zod";

  const getWeather = tool(
    async ({ city }) => {
      return `The weather in ${city} is always sunny!`;
    },
    {
      name: "get_weather",
      description: "Get weather for a given city.",
      schema: z.object({
        city: z.string(),
      }),
    },
  );

  const agent = createAgent({
    model: "openrouter:z-ai/glm-5.2",
    tools: [getWeather],
    checkpointer: new MemorySaver(),
  });

  const config = { configurable: { thread_id: uuid7() } };

  const stream = await agent.streamEvents(
    { messages: [{ role: "user", content: "what is the weather in sf" }] },
    { ...config, version: "v3" },
  );
  await Promise.all([
    (async () => {
      for await (const message of stream.messages) {
        for await (const token of message.text) {
          process.stdout.write(token);
        }
      }
    })(),
    (async () => {
      for await (const call of stream.toolCalls) {
        console.log(`\nTool call: ${call.name}(${JSON.stringify(call.input)})`);
        console.log(`Tool result: ${await call.output}`);
      }
    })(),
  ]);

  const finalState = await stream.output;
  // Tool call: get_weather({"city":"San Francisco"})
  // Tool result: [object ToolMessage]
  // According to the data I have, the weather in San Francisco is always sunny! Would you like current conditions or a short forecast for today or the next few days?
  ```

  ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, tool } from "langchain";
  import { uuid7 } from "langsmith";
  import { MemorySaver } from "@langchain/langgraph";
  import z from "zod";

  const getWeather = tool(
    async ({ city }) => {
      return `The weather in ${city} is always sunny!`;
    },
    {
      name: "get_weather",
      description: "Get weather for a given city.",
      schema: z.object({
        city: z.string(),
      }),
    },
  );

  const agent = createAgent({
    model: "fireworks:accounts/fireworks/models/glm-5p2",
    tools: [getWeather],
    checkpointer: new MemorySaver(),
  });

  const config = { configurable: { thread_id: uuid7() } };

  const stream = await agent.streamEvents(
    { messages: [{ role: "user", content: "what is the weather in sf" }] },
    { ...config, version: "v3" },
  );
  await Promise.all([
    (async () => {
      for await (const message of stream.messages) {
        for await (const token of message.text) {
          process.stdout.write(token);
        }
      }
    })(),
    (async () => {
      for await (const call of stream.toolCalls) {
        console.log(`\nTool call: ${call.name}(${JSON.stringify(call.input)})`);
        console.log(`Tool result: ${await call.output}`);
      }
    })(),
  ]);

  const finalState = await stream.output;
  // Tool call: get_weather({"city":"San Francisco"})
  // Tool result: [object ToolMessage]
  // According to the data I have, the weather in San Francisco is always sunny! Would you like current conditions or a short forecast for today or the next few days?
  ```

  ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, tool } from "langchain";
  import { uuid7 } from "langsmith";
  import { MemorySaver } from "@langchain/langgraph";
  import z from "zod";

  const getWeather = tool(
    async ({ city }) => {
      return `The weather in ${city} is always sunny!`;
    },
    {
      name: "get_weather",
      description: "Get weather for a given city.",
      schema: z.object({
        city: z.string(),
      }),
    },
  );

  const agent = createAgent({
    model: "baseten:zai-org/GLM-5.2",
    tools: [getWeather],
    checkpointer: new MemorySaver(),
  });

  const config = { configurable: { thread_id: uuid7() } };

  const stream = await agent.streamEvents(
    { messages: [{ role: "user", content: "what is the weather in sf" }] },
    { ...config, version: "v3" },
  );
  await Promise.all([
    (async () => {
      for await (const message of stream.messages) {
        for await (const token of message.text) {
          process.stdout.write(token);
        }
      }
    })(),
    (async () => {
      for await (const call of stream.toolCalls) {
        console.log(`\nTool call: ${call.name}(${JSON.stringify(call.input)})`);
        console.log(`Tool result: ${await call.output}`);
      }
    })(),
  ]);

  const finalState = await stream.output;
  // Tool call: get_weather({"city":"San Francisco"})
  // Tool result: [object ToolMessage]
  // According to the data I have, the weather in San Francisco is always sunny! Would you like current conditions or a short forecast for today or the next few days?
  ```

  ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, tool } from "langchain";
  import { uuid7 } from "langsmith";
  import { MemorySaver } from "@langchain/langgraph";
  import z from "zod";

  const getWeather = tool(
    async ({ city }) => {
      return `The weather in ${city} is always sunny!`;
    },
    {
      name: "get_weather",
      description: "Get weather for a given city.",
      schema: z.object({
        city: z.string(),
      }),
    },
  );

  const agent = createAgent({
    model: "ollama:north-mini-code-1.0",
    tools: [getWeather],
    checkpointer: new MemorySaver(),
  });

  const config = { configurable: { thread_id: uuid7() } };

  const stream = await agent.streamEvents(
    { messages: [{ role: "user", content: "what is the weather in sf" }] },
    { ...config, version: "v3" },
  );
  await Promise.all([
    (async () => {
      for await (const message of stream.messages) {
        for await (const token of message.text) {
          process.stdout.write(token);
        }
      }
    })(),
    (async () => {
      for await (const call of stream.toolCalls) {
        console.log(`\nTool call: ${call.name}(${JSON.stringify(call.input)})`);
        console.log(`Tool result: ${await call.output}`);
      }
    })(),
  ]);

  const finalState = await stream.output;
  // Tool call: get_weather({"city":"San Francisco"})
  // Tool result: [object ToolMessage]
  // According to the data I have, the weather in San Francisco is always sunny! Would you like current conditions or a short forecast for today or the next few days?
  ```
</CodeGroup>

<Card title="View example trace" icon="chart-line" href="https://smith.langchain.com/public/d4b012af-7fb4-4417-b327-e770969de2aa/r" arrow horizontal>
  Open a public LangSmith run for this example.
</Card>

<Note>
  Persisting conversation history with `thread_id` requires the agent to be configured with a [checkpointer](/oss/javascript/langchain/long-term-memory). On [LangSmith deployments](/langsmith/deployment) a checkpointer is provisioned automatically. Locally, pass one explicitly, for example `createAgent({ ..., checkpointer: new MemorySaver() })`. The remaining snippets on this page omit `thread_id` for brevity, but you should pass it in production.
</Note>

## LLM tokens

To stream tokens as they are produced by the LLM, use `streamMode: "messages"`:

```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
import z from "zod";
import { createAgent, tool } from "langchain";

const getWeather = tool(
    async ({ city }) => {
        return `The weather in ${city} is always sunny!`;
    },
    {
        name: "get_weather",
        description: "Get weather for a given city.",
        schema: z.object({
        city: z.string(),
        }),
    }
);

const agent = createAgent({
    model: "gpt-5.4-mini",
    tools: [getWeather],
});

for await (const [token, metadata] of await agent.stream(
    { messages: [{ role: "user", content: "what is the weather in sf" }] },
    { streamMode: "messages" }
)) {
    console.log(`node: ${metadata.langgraph_node}`);
    console.log(`content: ${JSON.stringify(token.contentBlocks, null, 2)}`);
}
```

<Note>
  **Wrapping an agent as a node in a parent `StateGraph`?** [`createAgent`](https://reference.langchain.com/javascript/langchain/index/createAgent) returns a `ReactAgent` wrapper; pass `agent.graph` when adding it as a node. Use `subgraphs: true` so message chunks include the subgraph namespace. See [Subgraph outputs](/oss/javascript/langgraph/streaming#subgraph-outputs).
</Note>

## Custom updates

To stream updates from tools as they are executed, you can use the `writer` parameter from the configuration.

```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
import z from "zod";
import { tool, createAgent } from "langchain";
import { LangGraphRunnableConfig } from "@langchain/langgraph";

const getWeather = tool(
    async (input, config: LangGraphRunnableConfig) => {
        // Stream any arbitrary data
        config.writer?.(`Looking up data for city: ${input.city}`);
        // ... fetch city data
        config.writer?.(`Acquired data for city: ${input.city}`);
        return `It's always sunny in ${input.city}!`;
    },
    {
        name: "get_weather",
        description: "Get weather for a given city.",
        schema: z.object({
        city: z.string().describe("The city to get weather for."),
        }),
    }
);

const agent = createAgent({
    model: "gpt-5.4-mini",
    tools: [getWeather],
});

for await (const chunk of await agent.stream(
    { messages: [{ role: "user", content: "what is the weather in sf" }] },
    { streamMode: "custom" }
)) {
    console.log(chunk);
}
```

```shell title="Output" theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
Looking up data for city: San Francisco
Acquired data for city: San Francisco
```

<Note>
  If you add the `writer` parameter to your tool, you won't be able to invoke the tool outside of a LangGraph execution context without providing a writer function.
</Note>

## Stream multiple modes

You can specify multiple streaming modes by passing streamMode as an array: `streamMode: ["updates", "messages", "custom"]`.

The streamed outputs will be tuples of `[mode, chunk]` where `mode` is the name of the stream mode and `chunk` is the data streamed by that mode.

```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
import z from "zod";
import { tool, createAgent } from "langchain";
import { LangGraphRunnableConfig } from "@langchain/langgraph";

const getWeather = tool(
    async (input, config: LangGraphRunnableConfig) => {
        // Stream any arbitrary data
        config.writer?.(`Looking up data for city: ${input.city}`);
        // ... fetch city data
        config.writer?.(`Acquired data for city: ${input.city}`);
        return `It's always sunny in ${input.city}!`;
    },
    {
        name: "get_weather",
        description: "Get weather for a given city.",
        schema: z.object({
        city: z.string().describe("The city to get weather for."),
        }),
    }
);

const agent = createAgent({
    model: "gpt-5.4-mini",
    tools: [getWeather],
});

for await (const [streamMode, chunk] of await agent.stream(
    { messages: [{ role: "user", content: "what is the weather in sf" }] },
    { streamMode: ["updates", "messages", "custom"] }
)) {
    console.log(`${streamMode}: ${JSON.stringify(chunk, null, 2)}`);
}
```

## Common patterns

Below are examples showing common use cases for streaming.

### Streaming thinking / reasoning tokens

Some models perform internal reasoning before producing a final answer. You can stream these thinking / reasoning tokens as they're generated by filtering [standard content blocks](/oss/javascript/langchain/messages#standard-content-blocks) for the `type` `"reasoning"`.

<Note>
  Reasoning output must be enabled on the model.

  See the [reasoning section](/oss/javascript/langchain/models#reasoning) and your [provider's integration page](/oss/javascript/integrations/providers/overview) for configuration details.

  To quickly check a model's reasoning support, see [models.dev](https://models.dev).
</Note>

To stream thinking tokens from an agent, use `streamMode: "messages"` and filter for reasoning content blocks. Use a model instance (e.g. `ChatAnthropic`) with extended thinking enabled when the model supports it:

```ts theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
import z from "zod";
import { createAgent, tool } from "langchain";
import { ChatAnthropic } from "@langchain/anthropic";

const getWeather = tool(
  async ({ city }) => {
    return `It's always sunny in ${city}!`;
  },
  {
    name: "get_weather",
    description: "Get weather for a given city.",
    schema: z.object({ city: z.string() }),
  },
);

const agent = createAgent({
  model: new ChatAnthropic({
    model: "claude-sonnet-4-6",
    thinking: { type: "enabled", budget_tokens: 5000 },
  }),
  tools: [getWeather],
});

const stream = await agent.streamEvents(
  { messages: [{ role: "user", content: "What is the weather in SF?" }] },
  { version: "v3" }, // [!code highlight]
);
for await (const message of stream.messages) {
  for await (const token of message.reasoning) {
    process.stdout.write(`[thinking] ${token}`);
  }
  for await (const token of message.text) {
    process.stdout.write(token);
  }
}
```

<Card title="View example trace" icon="chart-line" href="https://smith.langchain.com/public/1c167f24-489a-47da-b7df-0b4b21789d9b/r" arrow horizontal>
  Open a public LangSmith run for this example.
</Card>

```shell title="Output" theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
[thinking] The user is asking about the weather in San Francisco. I have a tool
[thinking]  available to get this information. Let me call the get_weather tool
[thinking]  with "San Francisco" as the city parameter.
The weather in San Francisco is: It's always sunny in San Francisco!
```

This works the same way regardless of the model provider—LangChain normalizes provider-specific formats (Anthropic `thinking` blocks, OpenAI `reasoning` summaries, etc.) into a standard `"reasoning"` content block type via the [`content_blocks`](/oss/javascript/langchain/messages#standard-content-blocks) property.

To stream reasoning tokens directly from a chat model (without an agent), see [streaming with chat models](/oss/javascript/langchain/models#reasoning).

## Disable streaming

In some applications you might need to disable streaming of individual tokens for a given model. This is useful when:

* Working with [multi-agent](/oss/javascript/langchain/multi-agent) systems to control which agents stream their output
* Mixing models that support streaming with those that do not
* Deploying to [LangSmith](/langsmith/observability) and wanting to prevent certain model outputs from being streamed to the client

Set `streaming: false` when initializing the model.

```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
import { ChatOpenAI } from "@langchain/openai";

const model = new ChatOpenAI({
  model: "gpt-5.5",
  streaming: false,  // [!code highlight]
});
```

<Tip>
  When deploying to LangSmith, set `streaming=False` on any models whose output you don't want streamed to the client. This is configured in your graph code before deployment.
</Tip>

<Note>
  Not all chat model integrations support the `streaming` parameter. If your model doesn't support it, use `disableStreaming: true` instead. This parameter is available on all chat models via the base class.
</Note>

See the [LangGraph streaming guide](/oss/javascript/langgraph/streaming#disable-streaming-for-specific-chat-models) for more details.

## Related

* [Frontend streaming](/oss/javascript/langchain/frontend/overview)—Build React UIs with [`useStream`](https://reference.langchain.com/javascript/langchain-react/index/useStream) for real-time agent interactions
* [Streaming with chat models](/oss/javascript/langchain/models#stream)—Stream tokens directly from a chat model without using an agent or graph
* [Reasoning with chat models](/oss/javascript/langchain/models#reasoning)—Configure and access reasoning output from chat models
* [Standard content blocks](/oss/javascript/langchain/messages#standard-content-blocks)—Understand the normalized content block format used for reasoning, text, and other content types
* [Streaming with human-in-the-loop](/oss/javascript/langchain/human-in-the-loop#streaming-with-human-in-the-loop)—Stream agent progress while handling interrupts for human review
* [LangGraph streaming](/oss/javascript/langgraph/streaming)—Advanced streaming options including `values`, `debug` modes, and subgraph streaming

***

<div className="source-links">
  <Callout icon="terminal-2">
    [Connect these docs](/use-these-docs) to your agent of choice via MCP for real-time answers.
  </Callout>

  <Callout icon="edit">
    [Edit this page on GitHub](https://github.com/langchain-ai/docs/edit/main/src/oss/langchain/streaming.mdx) or [file an issue](https://github.com/langchain-ai/docs/issues/new/choose).
  </Callout>
</div>
