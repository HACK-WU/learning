> ## Documentation Index
> Fetch the complete documentation index at: https://docs.langchain.com/llms.txt
> Use this file to discover all available pages before exploring further.

# Agents

> Build a LangChain agent: a model calling tools in a loop until a task is complete, shaped by a harness of prompt, tools, and middleware.

An agent is a model calling tools in a loop until a given task is complete.

<img src="https://mintcdn.com/langchain-5e9cc07a/jtty0O--UJOKG0nK/oss/images/core_agent_loop.svg?fit=max&auto=format&n=jtty0O--UJOKG0nK&q=85&s=4b4cbb497b6273758a565de1bc90ece0" alt="Core agent loop diagram" style={{height: "300px", width: "auto", justifyContent: "center"}} className="rounded-lg block mx-auto" width="1060" height="760" data-path="oss/images/core_agent_loop.svg" />

A harness is everything around that loop: the prompt, the tools, and any middleware that shapes the model's behavior.

<Note>
  **Agent = Model + Harness**

  The job of a harness: get the model the right context at the right time for the given task.
</Note>

[`create_agent`](https://reference.langchain.com/javascript/langchain/index/createAgent) is a highly configurable harness. At its simplest, you can create one with:

<CodeGroup>
  ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";

  var agent = createAgent({ model: "google:gemini-3.6-flash", tools });
  ```

  ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";

  var agent = createAgent({ model: "openai:gpt-5.5", tools });
  ```

  ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";

  var agent = createAgent({ model: "anthropic:claude-sonnet-5", tools });
  ```

  ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";

  var agent = createAgent({ model: "openrouter:z-ai/glm-5.2", tools });
  ```

  ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";

  var agent = createAgent({ model: "fireworks:accounts/fireworks/models/glm-5p2", tools });
  ```

  ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";

  var agent = createAgent({ model: "baseten:zai-org/GLM-5.2", tools });
  ```

  ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";

  var agent = createAgent({ model: "ollama:north-mini-code-1.0", tools });
  ```
</CodeGroup>

Building on that, you can configure the basics directly with the `model=`, `tools=`, and `system_prompt=` parameters. For more advanced capabilities, extend the harness with [middleware](#configure-the-harness).

<Tip>
  [Deep Agents](/oss/javascript/deepagents/overview) builds on `create_agent` and comes with commonly useful capabilities already assembled, such as planning, file system tools, subagents, and memory. Use `create_agent` when you need to configure the harness yourself.
</Tip>

## Core components

<img src="https://mintcdn.com/langchain-5e9cc07a/jtty0O--UJOKG0nK/oss/images/agent_model_harness.svg?fit=max&auto=format&n=jtty0O--UJOKG0nK&q=85&s=5ac6a7e0343af7cb5ba3ca632e2224af" alt="Agent model and harness components diagram" style={{height: "280px", width: "auto", justifyContent: "center"}} className="rounded-lg block mx-auto" width="1200" height="760" data-path="oss/images/agent_model_harness.svg" />

### Model

Pass a model identifier string (`"provider:model"`) or an initialized model instance to select the model for your agent. See [Models](/oss/javascript/langchain/models) for parameters, provider setup, and dynamic model selection.

<CodeGroup>
  ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";

  var agent = createAgent({ model: "google:gemini-3.6-flash", tools });
  ```

  ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";

  var agent = createAgent({ model: "openai:gpt-5.5", tools });
  ```

  ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";

  var agent = createAgent({ model: "anthropic:claude-sonnet-5", tools });
  ```

  ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";

  var agent = createAgent({ model: "openrouter:z-ai/glm-5.2", tools });
  ```

  ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";

  var agent = createAgent({ model: "fireworks:accounts/fireworks/models/glm-5p2", tools });
  ```

  ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";

  var agent = createAgent({ model: "baseten:zai-org/GLM-5.2", tools });
  ```

  ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";

  var agent = createAgent({ model: "ollama:north-mini-code-1.0", tools });
  ```
</CodeGroup>

### Tools

To provide the agent with tools, pass any Python callable, LangChain tool, or tool dict. See [Tools](/oss/javascript/langchain/tools) for tool definition, context access, and dynamic tool selection.

<CodeGroup>
  ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Results for: ${query}`, {
    name: "search",
    description: "Search for information",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({ model: "google:gemini-3.6-flash", tools: [search] });
  ```

  ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Results for: ${query}`, {
    name: "search",
    description: "Search for information",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({ model: "openai:gpt-5.5", tools: [search] });
  ```

  ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Results for: ${query}`, {
    name: "search",
    description: "Search for information",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({ model: "anthropic:claude-sonnet-5", tools: [search] });
  ```

  ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Results for: ${query}`, {
    name: "search",
    description: "Search for information",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({ model: "openrouter:z-ai/glm-5.2", tools: [search] });
  ```

  ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Results for: ${query}`, {
    name: "search",
    description: "Search for information",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({ model: "fireworks:accounts/fireworks/models/glm-5p2", tools: [search] });
  ```

  ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Results for: ${query}`, {
    name: "search",
    description: "Search for information",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({ model: "baseten:zai-org/GLM-5.2", tools: [search] });
  ```

  ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Results for: ${query}`, {
    name: "search",
    description: "Search for information",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({ model: "ollama:north-mini-code-1.0", tools: [search] });
  ```
</CodeGroup>

### System prompt

Shape how the agent approaches tasks. The system prompt parameter accepts a string or `SystemMessage`. For dynamic prompts at runtime, use [middleware](/oss/javascript/langchain/middleware).

<CodeGroup>
  ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  var agent = createAgent({
    model: "google:gemini-3.6-flash",
    tools,
    systemPrompt: "You are a helpful assistant. Be concise and accurate.",
  });
  ```

  ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  var agent = createAgent({
    model: "openai:gpt-5.5",
    tools,
    systemPrompt: "You are a helpful assistant. Be concise and accurate.",
  });
  ```

  ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  var agent = createAgent({
    model: "anthropic:claude-sonnet-5",
    tools,
    systemPrompt: "You are a helpful assistant. Be concise and accurate.",
  });
  ```

  ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  var agent = createAgent({
    model: "openrouter:z-ai/glm-5.2",
    tools,
    systemPrompt: "You are a helpful assistant. Be concise and accurate.",
  });
  ```

  ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  var agent = createAgent({
    model: "fireworks:accounts/fireworks/models/glm-5p2",
    tools,
    systemPrompt: "You are a helpful assistant. Be concise and accurate.",
  });
  ```

  ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  var agent = createAgent({
    model: "baseten:zai-org/GLM-5.2",
    tools,
    systemPrompt: "You are a helpful assistant. Be concise and accurate.",
  });
  ```

  ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  var agent = createAgent({
    model: "ollama:north-mini-code-1.0",
    tools,
    systemPrompt: "You are a helpful assistant. Be concise and accurate.",
  });
  ```
</CodeGroup>

### Structured output

Return a validated schema from the agent using `response_format=`. See [Structured output](/oss/javascript/langchain/structured-output) for strategies and examples.

<CodeGroup>
  ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  const Answer = z.object({ summary: z.string(), confidence: z.number() });

  var agent = createAgent({
    model: "google:gemini-3.6-flash",
    tools,
    responseFormat: Answer,
  });
  const result = await agent.invoke({
    messages: [{ role: "user", content: "Summarize AI trends" }],
  });
  result.structuredResponse; // { summary: ..., confidence: ... }
  ```

  ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  const Answer = z.object({ summary: z.string(), confidence: z.number() });

  var agent = createAgent({
    model: "openai:gpt-5.5",
    tools,
    responseFormat: Answer,
  });
  const result = await agent.invoke({
    messages: [{ role: "user", content: "Summarize AI trends" }],
  });
  result.structuredResponse; // { summary: ..., confidence: ... }
  ```

  ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  const Answer = z.object({ summary: z.string(), confidence: z.number() });

  var agent = createAgent({
    model: "anthropic:claude-sonnet-5",
    tools,
    responseFormat: Answer,
  });
  const result = await agent.invoke({
    messages: [{ role: "user", content: "Summarize AI trends" }],
  });
  result.structuredResponse; // { summary: ..., confidence: ... }
  ```

  ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  const Answer = z.object({ summary: z.string(), confidence: z.number() });

  var agent = createAgent({
    model: "openrouter:z-ai/glm-5.2",
    tools,
    responseFormat: Answer,
  });
  const result = await agent.invoke({
    messages: [{ role: "user", content: "Summarize AI trends" }],
  });
  result.structuredResponse; // { summary: ..., confidence: ... }
  ```

  ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  const Answer = z.object({ summary: z.string(), confidence: z.number() });

  var agent = createAgent({
    model: "fireworks:accounts/fireworks/models/glm-5p2",
    tools,
    responseFormat: Answer,
  });
  const result = await agent.invoke({
    messages: [{ role: "user", content: "Summarize AI trends" }],
  });
  result.structuredResponse; // { summary: ..., confidence: ... }
  ```

  ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  const Answer = z.object({ summary: z.string(), confidence: z.number() });

  var agent = createAgent({
    model: "baseten:zai-org/GLM-5.2",
    tools,
    responseFormat: Answer,
  });
  const result = await agent.invoke({
    messages: [{ role: "user", content: "Summarize AI trends" }],
  });
  result.structuredResponse; // { summary: ..., confidence: ... }
  ```

  ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  const Answer = z.object({ summary: z.string(), confidence: z.number() });

  var agent = createAgent({
    model: "ollama:north-mini-code-1.0",
    tools,
    responseFormat: Answer,
  });
  const result = await agent.invoke({
    messages: [{ role: "user", content: "Summarize AI trends" }],
  });
  result.structuredResponse; // { summary: ..., confidence: ... }
  ```
</CodeGroup>

### Agent state

Every agent manages its execution context through an `AgentState` object that holds the current conversation history and any custom fields your tools and middleware need.

The built-in field is:

| Field | Type | Description |
| - | - | - |
| `messages` | `BaseMessage[]` | The full conversation history for the current thread. Append-only: new messages are added, never replaced. |

`AgentState` is also the type passed to every node-style middleware hook (`beforeModel`, `afterModel`, and similar). Hooks receive the current state and can return an object of updates to merge back into it.

To add custom fields, define a state schema on your middleware using `stateSchema` with a `StateSchema` or Zod object:

<CodeGroup>
  ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, createMiddleware } from "langchain";
  import { StateSchema } from "@langchain/langgraph";
  import * as z from "zod";

  const MyState = new StateSchema({
    userId: z.string(),
    callCount: z.number().default(0),
  });

  const stateMiddleware = createMiddleware({
    name: "StateExtension",
    stateSchema: MyState, // [!code highlight]
  });

  const agent = createAgent({
    model: "google:gemini-3.6-flash",
    tools: [],
    middleware: [stateMiddleware],
  });
  ```

  ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, createMiddleware } from "langchain";
  import { StateSchema } from "@langchain/langgraph";
  import * as z from "zod";

  const MyState = new StateSchema({
    userId: z.string(),
    callCount: z.number().default(0),
  });

  const stateMiddleware = createMiddleware({
    name: "StateExtension",
    stateSchema: MyState, // [!code highlight]
  });

  const agent = createAgent({
    model: "openai:gpt-5.5",
    tools: [],
    middleware: [stateMiddleware],
  });
  ```

  ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, createMiddleware } from "langchain";
  import { StateSchema } from "@langchain/langgraph";
  import * as z from "zod";

  const MyState = new StateSchema({
    userId: z.string(),
    callCount: z.number().default(0),
  });

  const stateMiddleware = createMiddleware({
    name: "StateExtension",
    stateSchema: MyState, // [!code highlight]
  });

  const agent = createAgent({
    model: "anthropic:claude-sonnet-5",
    tools: [],
    middleware: [stateMiddleware],
  });
  ```

  ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, createMiddleware } from "langchain";
  import { StateSchema } from "@langchain/langgraph";
  import * as z from "zod";

  const MyState = new StateSchema({
    userId: z.string(),
    callCount: z.number().default(0),
  });

  const stateMiddleware = createMiddleware({
    name: "StateExtension",
    stateSchema: MyState, // [!code highlight]
  });

  const agent = createAgent({
    model: "openrouter:z-ai/glm-5.2",
    tools: [],
    middleware: [stateMiddleware],
  });
  ```

  ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, createMiddleware } from "langchain";
  import { StateSchema } from "@langchain/langgraph";
  import * as z from "zod";

  const MyState = new StateSchema({
    userId: z.string(),
    callCount: z.number().default(0),
  });

  const stateMiddleware = createMiddleware({
    name: "StateExtension",
    stateSchema: MyState, // [!code highlight]
  });

  const agent = createAgent({
    model: "fireworks:accounts/fireworks/models/glm-5p2",
    tools: [],
    middleware: [stateMiddleware],
  });
  ```

  ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, createMiddleware } from "langchain";
  import { StateSchema } from "@langchain/langgraph";
  import * as z from "zod";

  const MyState = new StateSchema({
    userId: z.string(),
    callCount: z.number().default(0),
  });

  const stateMiddleware = createMiddleware({
    name: "StateExtension",
    stateSchema: MyState, // [!code highlight]
  });

  const agent = createAgent({
    model: "baseten:zai-org/GLM-5.2",
    tools: [],
    middleware: [stateMiddleware],
  });
  ```

  ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, createMiddleware } from "langchain";
  import { StateSchema } from "@langchain/langgraph";
  import * as z from "zod";

  const MyState = new StateSchema({
    userId: z.string(),
    callCount: z.number().default(0),
  });

  const stateMiddleware = createMiddleware({
    name: "StateExtension",
    stateSchema: MyState, // [!code highlight]
  });

  const agent = createAgent({
    model: "ollama:north-mini-code-1.0",
    tools: [],
    middleware: [stateMiddleware],
  });
  ```
</CodeGroup>

For full details, examples, and middleware-level state schemas, see [Short-term memory](/oss/javascript/langchain/short-term-memory#customizing-agent-memory) and [Custom middleware](/oss/javascript/langchain/middleware/custom#state-updates).

## Invocation

<Tip>
  Trace each step of this loop, debug tool calls, and evaluate agent outputs with [LangSmith](https://smith.langchain.com?utm_source=docs\&utm_medium=cta\&utm_campaign=langsmith-signup\&utm_content=oss-langchain-agents). Follow the [tracing quickstart](/langsmith/trace-with-langchain) to get set up. We recommend you also set up [LangSmith Engine](/langsmith/engine) which monitors your traces, detects issues, and proposes fixes.
</Tip>

You can invoke an agent with a message. Behind the scenes that passes an update to the agent's [`State`](/oss/javascript/langgraph/graph-api#state). All agents include a [sequence of messages](/oss/javascript/langgraph/use-graph-api#messagesvalue) in their state; to invoke the agent, pass a new message along with a `thread_id` so the agent can persist and resume conversation history:

<CodeGroup>
  ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { AIMessage } from "@langchain/core/messages";
  import { uuid7 } from "langsmith";
  import { createAgent } from "langchain";
  import { MemorySaver } from "@langchain/langgraph";

  const agent = createAgent({
    model: "google:gemini-3.6-flash",
    tools: [],
    checkpointer: new MemorySaver(),
  });

  const config = { configurable: { thread_id: uuid7() } };

  let result = await agent.invoke(
    {
      messages: [
        { role: "user", content: "What's the weather in San Francisco?" },
      ],
    },
    config,
  );

  // A follow-up turn on the same conversation: reuse the same thread_id to keep history
  result = await agent.invoke(
    { messages: [{ role: "user", content: "What about tomorrow?" }] },
    config,
  );
  ```

  ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { AIMessage } from "@langchain/core/messages";
  import { uuid7 } from "langsmith";
  import { createAgent } from "langchain";
  import { MemorySaver } from "@langchain/langgraph";

  const agent = createAgent({
    model: "openai:gpt-5.5",
    tools: [],
    checkpointer: new MemorySaver(),
  });

  const config = { configurable: { thread_id: uuid7() } };

  let result = await agent.invoke(
    {
      messages: [
        { role: "user", content: "What's the weather in San Francisco?" },
      ],
    },
    config,
  );

  // A follow-up turn on the same conversation: reuse the same thread_id to keep history
  result = await agent.invoke(
    { messages: [{ role: "user", content: "What about tomorrow?" }] },
    config,
  );
  ```

  ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { AIMessage } from "@langchain/core/messages";
  import { uuid7 } from "langsmith";
  import { createAgent } from "langchain";
  import { MemorySaver } from "@langchain/langgraph";

  const agent = createAgent({
    model: "anthropic:claude-sonnet-5",
    tools: [],
    checkpointer: new MemorySaver(),
  });

  const config = { configurable: { thread_id: uuid7() } };

  let result = await agent.invoke(
    {
      messages: [
        { role: "user", content: "What's the weather in San Francisco?" },
      ],
    },
    config,
  );

  // A follow-up turn on the same conversation: reuse the same thread_id to keep history
  result = await agent.invoke(
    { messages: [{ role: "user", content: "What about tomorrow?" }] },
    config,
  );
  ```

  ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { AIMessage } from "@langchain/core/messages";
  import { uuid7 } from "langsmith";
  import { createAgent } from "langchain";
  import { MemorySaver } from "@langchain/langgraph";

  const agent = createAgent({
    model: "openrouter:z-ai/glm-5.2",
    tools: [],
    checkpointer: new MemorySaver(),
  });

  const config = { configurable: { thread_id: uuid7() } };

  let result = await agent.invoke(
    {
      messages: [
        { role: "user", content: "What's the weather in San Francisco?" },
      ],
    },
    config,
  );

  // A follow-up turn on the same conversation: reuse the same thread_id to keep history
  result = await agent.invoke(
    { messages: [{ role: "user", content: "What about tomorrow?" }] },
    config,
  );
  ```

  ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { AIMessage } from "@langchain/core/messages";
  import { uuid7 } from "langsmith";
  import { createAgent } from "langchain";
  import { MemorySaver } from "@langchain/langgraph";

  const agent = createAgent({
    model: "fireworks:accounts/fireworks/models/glm-5p2",
    tools: [],
    checkpointer: new MemorySaver(),
  });

  const config = { configurable: { thread_id: uuid7() } };

  let result = await agent.invoke(
    {
      messages: [
        { role: "user", content: "What's the weather in San Francisco?" },
      ],
    },
    config,
  );

  // A follow-up turn on the same conversation: reuse the same thread_id to keep history
  result = await agent.invoke(
    { messages: [{ role: "user", content: "What about tomorrow?" }] },
    config,
  );
  ```

  ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { AIMessage } from "@langchain/core/messages";
  import { uuid7 } from "langsmith";
  import { createAgent } from "langchain";
  import { MemorySaver } from "@langchain/langgraph";

  const agent = createAgent({
    model: "baseten:zai-org/GLM-5.2",
    tools: [],
    checkpointer: new MemorySaver(),
  });

  const config = { configurable: { thread_id: uuid7() } };

  let result = await agent.invoke(
    {
      messages: [
        { role: "user", content: "What's the weather in San Francisco?" },
      ],
    },
    config,
  );

  // A follow-up turn on the same conversation: reuse the same thread_id to keep history
  result = await agent.invoke(
    { messages: [{ role: "user", content: "What about tomorrow?" }] },
    config,
  );
  ```

  ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { AIMessage } from "@langchain/core/messages";
  import { uuid7 } from "langsmith";
  import { createAgent } from "langchain";
  import { MemorySaver } from "@langchain/langgraph";

  const agent = createAgent({
    model: "ollama:north-mini-code-1.0",
    tools: [],
    checkpointer: new MemorySaver(),
  });

  const config = { configurable: { thread_id: uuid7() } };

  let result = await agent.invoke(
    {
      messages: [
        { role: "user", content: "What's the weather in San Francisco?" },
      ],
    },
    config,
  );

  // A follow-up turn on the same conversation: reuse the same thread_id to keep history
  result = await agent.invoke(
    { messages: [{ role: "user", content: "What about tomorrow?" }] },
    config,
  );
  ```
</CodeGroup>

<Card title="View example trace" icon="chart-line" href="https://smith.langchain.com/public/dc6c669f-1699-4c3c-8490-c02b7d2cf978/r" arrow horizontal>
  Open a public LangSmith run for this example.
</Card>

<Note>
  Persisting conversation history with `thread_id` requires the agent to be configured with a [checkpointer](/oss/javascript/langchain/long-term-memory). When deployed on [LangSmith](/langsmith/deployment), a checkpointer is provisioned automatically. Locally, pass one explicitly, for example `create_agent(..., checkpointer=InMemorySaver())`.
</Note>

If you also need to pass per-run configuration (such as a user ID, API keys, or feature flags) to tools and middleware, pass it as `context` alongside the config. Define the shape of that data with `contextSchema` and access it through `runtime.context`:

<CodeGroup>
  ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import * as z from "zod";
  import { uuid7 } from "langsmith";
  import { AIMessage } from "@langchain/core/messages";
  import { createAgent } from "langchain";
  import { MemorySaver } from "@langchain/langgraph";

  const contextSchema = z.object({
    user_id: z.string(),
  });

  const agent = createAgent({
    model: "google:gemini-3.6-flash",
    tools: [],
    contextSchema,
    checkpointer: new MemorySaver(),
  });

  const result = await agent.invoke(
    {
      messages: [
        { role: "user", content: "What's the weather in San Francisco?" },
      ],
    },
    {
      configurable: { thread_id: uuid7() },
      context: { user_id: "user-123" },
    },
  );
  ```

  ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import * as z from "zod";
  import { uuid7 } from "langsmith";
  import { AIMessage } from "@langchain/core/messages";
  import { createAgent } from "langchain";
  import { MemorySaver } from "@langchain/langgraph";

  const contextSchema = z.object({
    user_id: z.string(),
  });

  const agent = createAgent({
    model: "openai:gpt-5.5",
    tools: [],
    contextSchema,
    checkpointer: new MemorySaver(),
  });

  const result = await agent.invoke(
    {
      messages: [
        { role: "user", content: "What's the weather in San Francisco?" },
      ],
    },
    {
      configurable: { thread_id: uuid7() },
      context: { user_id: "user-123" },
    },
  );
  ```

  ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import * as z from "zod";
  import { uuid7 } from "langsmith";
  import { AIMessage } from "@langchain/core/messages";
  import { createAgent } from "langchain";
  import { MemorySaver } from "@langchain/langgraph";

  const contextSchema = z.object({
    user_id: z.string(),
  });

  const agent = createAgent({
    model: "anthropic:claude-sonnet-5",
    tools: [],
    contextSchema,
    checkpointer: new MemorySaver(),
  });

  const result = await agent.invoke(
    {
      messages: [
        { role: "user", content: "What's the weather in San Francisco?" },
      ],
    },
    {
      configurable: { thread_id: uuid7() },
      context: { user_id: "user-123" },
    },
  );
  ```

  ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import * as z from "zod";
  import { uuid7 } from "langsmith";
  import { AIMessage } from "@langchain/core/messages";
  import { createAgent } from "langchain";
  import { MemorySaver } from "@langchain/langgraph";

  const contextSchema = z.object({
    user_id: z.string(),
  });

  const agent = createAgent({
    model: "openrouter:z-ai/glm-5.2",
    tools: [],
    contextSchema,
    checkpointer: new MemorySaver(),
  });

  const result = await agent.invoke(
    {
      messages: [
        { role: "user", content: "What's the weather in San Francisco?" },
      ],
    },
    {
      configurable: { thread_id: uuid7() },
      context: { user_id: "user-123" },
    },
  );
  ```

  ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import * as z from "zod";
  import { uuid7 } from "langsmith";
  import { AIMessage } from "@langchain/core/messages";
  import { createAgent } from "langchain";
  import { MemorySaver } from "@langchain/langgraph";

  const contextSchema = z.object({
    user_id: z.string(),
  });

  const agent = createAgent({
    model: "fireworks:accounts/fireworks/models/glm-5p2",
    tools: [],
    contextSchema,
    checkpointer: new MemorySaver(),
  });

  const result = await agent.invoke(
    {
      messages: [
        { role: "user", content: "What's the weather in San Francisco?" },
      ],
    },
    {
      configurable: { thread_id: uuid7() },
      context: { user_id: "user-123" },
    },
  );
  ```

  ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import * as z from "zod";
  import { uuid7 } from "langsmith";
  import { AIMessage } from "@langchain/core/messages";
  import { createAgent } from "langchain";
  import { MemorySaver } from "@langchain/langgraph";

  const contextSchema = z.object({
    user_id: z.string(),
  });

  const agent = createAgent({
    model: "baseten:zai-org/GLM-5.2",
    tools: [],
    contextSchema,
    checkpointer: new MemorySaver(),
  });

  const result = await agent.invoke(
    {
      messages: [
        { role: "user", content: "What's the weather in San Francisco?" },
      ],
    },
    {
      configurable: { thread_id: uuid7() },
      context: { user_id: "user-123" },
    },
  );
  ```

  ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import * as z from "zod";
  import { uuid7 } from "langsmith";
  import { AIMessage } from "@langchain/core/messages";
  import { createAgent } from "langchain";
  import { MemorySaver } from "@langchain/langgraph";

  const contextSchema = z.object({
    user_id: z.string(),
  });

  const agent = createAgent({
    model: "ollama:north-mini-code-1.0",
    tools: [],
    contextSchema,
    checkpointer: new MemorySaver(),
  });

  const result = await agent.invoke(
    {
      messages: [
        { role: "user", content: "What's the weather in San Francisco?" },
      ],
    },
    {
      configurable: { thread_id: uuid7() },
      context: { user_id: "user-123" },
    },
  );
  ```
</CodeGroup>

<Card title="View example trace" icon="chart-line" href="https://smith.langchain.com/public/3bc1fb83-7ada-4e78-b9ac-31b749201c7d/r" arrow horizontal>
  Open a public LangSmith run for this example.
</Card>

`thread_id` scopes the *conversation* (message history, checkpoints), while `context` carries *per-run* data your tools and middleware read at invocation time. Both are commonly passed together. See [tool context](/oss/javascript/langchain/tools#context) and [Runtime](/oss/javascript/langchain/runtime) for more.

## Streaming

`invoke` returns the final response at the end of a run. If an agent executes multiple tool calls, users often need progress updates before completion. Use streaming to surface intermediate messages and tool activity as they happen.

```ts theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
const stream = await agent.streamEvents(
  {
    messages: [
      {
        role: "user",
        content: "Search for AI news and summarize the findings",
      },
    ],
  },
  { version: "v3" },
);

for await (const snapshot of stream.values) {
  // Each snapshot contains the full state at that point
  const latestMessage = snapshot.messages.at(-1);
  if (latestMessage?.content) {
    if (latestMessage.type === "human") {
      console.log(`User: ${latestMessage.content}`);
    } else if (latestMessage.type === "ai") {
      console.log(`Agent: ${latestMessage.content}`);
    }
  } else if (latestMessage?.tool_calls?.length) {
    const toolCallNames = latestMessage.tool_calls.map((tc) => tc.name);
    console.log(`Calling tools: ${toolCallNames.join(", ")}`);
  }
}
```

<Card title="View example trace" icon="chart-line" href="https://smith.langchain.com/public/53397253-6f2d-47c6-aa4e-a701377341e7/r" arrow horizontal>
  Open a public LangSmith run for this example.
</Card>

<Tip>
  For streaming modes, event types, and UI patterns, see [Streaming](/oss/javascript/langchain/streaming).
</Tip>

## Configure the harness

`create_agent` is highly extensible. Middleware is the primitive for customization: each piece handles one concern, hooks into the agent loop at the right moment, and composes freely with any other. Take exactly what your use case needs and skip the rest.

Common patterns are prebuilt as first-class middleware. You can build anything else as [custom middleware](/oss/javascript/langchain/middleware/custom).

<img src="https://mintcdn.com/langchain-5e9cc07a/jtty0O--UJOKG0nK/oss/images/agent_harness_capabilities.svg?fit=max&auto=format&n=jtty0O--UJOKG0nK&q=85&s=0ff671d72badd0844826660dfcb04391" alt="Agent harness capabilities by category" style={{height: "300px", width: "auto", justifyContent: "center"}} className="rounded-lg block mx-auto" width="1500" height="360" data-path="oss/images/agent_harness_capabilities.svg" />

As agents take on complex work, they need support across a few key areas. The middleware ecosystem provides:

<CardGroup cols={2}>
  <Card title="Execution environment" icon="bolt" href="#execution-environment">
    Tools, filesystem, sandboxes, and code execution
  </Card>

  <Card title="Context management" icon="database" href="#context-management">
    Summarization, memory, skills, and prompt caching
  </Card>

  <Card title="Planning and delegation" icon="sitemap" href="#planning-and-delegation">
    Todo lists and subagents for parallel, isolated work
  </Card>

  <Card title="Fault tolerance" icon="shield" href="#fault-tolerance">
    Retries, fallbacks, and call limits
  </Card>

  <Card title="Guardrails" icon="lock" href="#guardrails">
    PII detection and content controls
  </Card>

  <Card title="Steering" icon="user" href="#steering">
    Human-in-the-loop approval before high-impact actions
  </Card>
</CardGroup>

<Tip>
  `create_deep_agent` pre-assembles this stack for long-running coding and research tasks (filesystem, summarization, subagents, and prompt caching included by default). See [Deep Agents](/oss/javascript/deepagents/harness) for the full prebuilt harness.
</Tip>

### Execution environment

Agents are especially useful when they can take action rather than just generate text. The execution environment gives the agent a workspace: tools it can call, a filesystem for reading and writing files across turns, and code execution for running scripts or shell commands.

<CodeGroup>
  ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";
  import { createFilesystemMiddleware, StateBackend } from "deepagents";

  var agent = createAgent({
    model: "google:gemini-3.6-flash",
    tools: [search],
    middleware: [createFilesystemMiddleware({ backend: new StateBackend() })],
  });
  ```

  ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";
  import { createFilesystemMiddleware, StateBackend } from "deepagents";

  var agent = createAgent({
    model: "openai:gpt-5.5",
    tools: [search],
    middleware: [createFilesystemMiddleware({ backend: new StateBackend() })],
  });
  ```

  ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";
  import { createFilesystemMiddleware, StateBackend } from "deepagents";

  var agent = createAgent({
    model: "anthropic:claude-sonnet-5",
    tools: [search],
    middleware: [createFilesystemMiddleware({ backend: new StateBackend() })],
  });
  ```

  ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";
  import { createFilesystemMiddleware, StateBackend } from "deepagents";

  var agent = createAgent({
    model: "openrouter:z-ai/glm-5.2",
    tools: [search],
    middleware: [createFilesystemMiddleware({ backend: new StateBackend() })],
  });
  ```

  ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";
  import { createFilesystemMiddleware, StateBackend } from "deepagents";

  var agent = createAgent({
    model: "fireworks:accounts/fireworks/models/glm-5p2",
    tools: [search],
    middleware: [createFilesystemMiddleware({ backend: new StateBackend() })],
  });
  ```

  ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";
  import { createFilesystemMiddleware, StateBackend } from "deepagents";

  var agent = createAgent({
    model: "baseten:zai-org/GLM-5.2",
    tools: [search],
    middleware: [createFilesystemMiddleware({ backend: new StateBackend() })],
  });
  ```

  ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";
  import { createFilesystemMiddleware, StateBackend } from "deepagents";

  var agent = createAgent({
    model: "ollama:north-mini-code-1.0",
    tools: [search],
    middleware: [createFilesystemMiddleware({ backend: new StateBackend() })],
  });
  ```
</CodeGroup>

See [`FilesystemMiddleware`](https://reference.langchain.com/javascript/deepagents/middleware/createFilesystemMiddleware), [Sandboxes](/oss/javascript/deepagents/sandboxes), [Interpreters](/oss/javascript/deepagents/interpreters).

<Note>
  This example imports from the `deepagents` package. Install it with:

  <CodeGroup>
    ```bash npm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    npm install deepagents
    ```

    ```bash yarn theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    yarn add deepagents
    ```

    ```bash pnpm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    pnpm add deepagents
    ```
  </CodeGroup>
</Note>

### Context management

Every model call has a fixed context window. As an agent runs, that window fills with accumulating history, tool results, and intermediate steps. Summarization compresses history before overflow hits; memory loads persistent instructions at startup so knowledge carries across sessions; skills surface domain knowledge on demand rather than loading everything upfront.

<CodeGroup>
  ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";
  import {
    StateBackend,
    createFilesystemMiddleware,
    createSkillsMiddleware,
    createSummarizationMiddleware,
  } from "deepagents";

  var backend = new StateBackend();
  const model = "google:gemini-3.6-flash";

  var agent = createAgent({
    model,
    tools: [search],
    middleware: [
      createFilesystemMiddleware({ backend }),
      createSummarizationMiddleware({ model, backend }),
      createSkillsMiddleware({ backend, sources: ["./skills/"] }),
    ],
  });
  ```

  ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";
  import {
    StateBackend,
    createFilesystemMiddleware,
    createSkillsMiddleware,
    createSummarizationMiddleware,
  } from "deepagents";

  var backend = new StateBackend();
  const model = "openai:gpt-5.5";

  var agent = createAgent({
    model,
    tools: [search],
    middleware: [
      createFilesystemMiddleware({ backend }),
      createSummarizationMiddleware({ model, backend }),
      createSkillsMiddleware({ backend, sources: ["./skills/"] }),
    ],
  });
  ```

  ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";
  import {
    StateBackend,
    createFilesystemMiddleware,
    createSkillsMiddleware,
    createSummarizationMiddleware,
  } from "deepagents";

  var backend = new StateBackend();
  const model = "anthropic:claude-sonnet-5";

  var agent = createAgent({
    model,
    tools: [search],
    middleware: [
      createFilesystemMiddleware({ backend }),
      createSummarizationMiddleware({ model, backend }),
      createSkillsMiddleware({ backend, sources: ["./skills/"] }),
    ],
  });
  ```

  ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";
  import {
    StateBackend,
    createFilesystemMiddleware,
    createSkillsMiddleware,
    createSummarizationMiddleware,
  } from "deepagents";

  var backend = new StateBackend();
  const model = "openrouter:z-ai/glm-5.2";

  var agent = createAgent({
    model,
    tools: [search],
    middleware: [
      createFilesystemMiddleware({ backend }),
      createSummarizationMiddleware({ model, backend }),
      createSkillsMiddleware({ backend, sources: ["./skills/"] }),
    ],
  });
  ```

  ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";
  import {
    StateBackend,
    createFilesystemMiddleware,
    createSkillsMiddleware,
    createSummarizationMiddleware,
  } from "deepagents";

  var backend = new StateBackend();
  const model = "fireworks:accounts/fireworks/models/glm-5p2";

  var agent = createAgent({
    model,
    tools: [search],
    middleware: [
      createFilesystemMiddleware({ backend }),
      createSummarizationMiddleware({ model, backend }),
      createSkillsMiddleware({ backend, sources: ["./skills/"] }),
    ],
  });
  ```

  ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";
  import {
    StateBackend,
    createFilesystemMiddleware,
    createSkillsMiddleware,
    createSummarizationMiddleware,
  } from "deepagents";

  var backend = new StateBackend();
  const model = "baseten:zai-org/GLM-5.2";

  var agent = createAgent({
    model,
    tools: [search],
    middleware: [
      createFilesystemMiddleware({ backend }),
      createSummarizationMiddleware({ model, backend }),
      createSkillsMiddleware({ backend, sources: ["./skills/"] }),
    ],
  });
  ```

  ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent } from "langchain";
  import {
    StateBackend,
    createFilesystemMiddleware,
    createSkillsMiddleware,
    createSummarizationMiddleware,
  } from "deepagents";

  var backend = new StateBackend();
  const model = "ollama:north-mini-code-1.0";

  var agent = createAgent({
    model,
    tools: [search],
    middleware: [
      createFilesystemMiddleware({ backend }),
      createSummarizationMiddleware({ model, backend }),
      createSkillsMiddleware({ backend, sources: ["./skills/"] }),
    ],
  });
  ```
</CodeGroup>

See [`SummarizationMiddleware`](https://reference.langchain.com/javascript/langchain/index/summarizationMiddleware), [`MemoryMiddleware`](https://reference.langchain.com/javascript/deepagents/middleware/createMemoryMiddleware), [Skills](/oss/javascript/langchain/multi-agent/skills), [Context engineering](/oss/javascript/deepagents/context-engineering).

<Note>
  This example imports from the `deepagents` package. Install it with:

  <CodeGroup>
    ```bash npm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    npm install deepagents
    ```

    ```bash yarn theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    yarn add deepagents
    ```

    ```bash pnpm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    pnpm add deepagents
    ```
  </CodeGroup>
</Note>

### Planning and delegation

Complex tasks often exceed what one context window can handle. Delegation lets the main agent break work into pieces, hand them to subagents that each run in their own isolated context, and stay focused on coordination rather than execution. Work can run in parallel; the main agent's context stays clean.

<CodeGroup>
  ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, todoListMiddleware, tool } from "langchain";
  import {
    createFilesystemMiddleware,
    createSubAgentMiddleware,
    StateBackend,
  } from "deepagents";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var backend = new StateBackend();

  var agent = createAgent({
    model: "google:gemini-3.6-flash",
    tools: [search],
    middleware: [
      createFilesystemMiddleware({ backend }),
      todoListMiddleware(),
      createSubAgentMiddleware({
        defaultModel: "anthropic:claude-sonnet-4-6",
        defaultTools: [],
        subagents: [
          {
            name: "researcher",
            description: "Searches and returns a structured summary.",
            systemPrompt:
              "Use the search tool to research the question and summarize key points.",
            tools: [search],
            model: "google:gemini-3.6-flash",
            middleware: [],
          },
        ],
      }),
    ],
  });
  ```

  ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, todoListMiddleware, tool } from "langchain";
  import {
    createFilesystemMiddleware,
    createSubAgentMiddleware,
    StateBackend,
  } from "deepagents";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var backend = new StateBackend();

  var agent = createAgent({
    model: "openai:gpt-5.5",
    tools: [search],
    middleware: [
      createFilesystemMiddleware({ backend }),
      todoListMiddleware(),
      createSubAgentMiddleware({
        defaultModel: "anthropic:claude-sonnet-4-6",
        defaultTools: [],
        subagents: [
          {
            name: "researcher",
            description: "Searches and returns a structured summary.",
            systemPrompt:
              "Use the search tool to research the question and summarize key points.",
            tools: [search],
            model: "openai:gpt-5.5",
            middleware: [],
          },
        ],
      }),
    ],
  });
  ```

  ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, todoListMiddleware, tool } from "langchain";
  import {
    createFilesystemMiddleware,
    createSubAgentMiddleware,
    StateBackend,
  } from "deepagents";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var backend = new StateBackend();

  var agent = createAgent({
    model: "anthropic:claude-sonnet-5",
    tools: [search],
    middleware: [
      createFilesystemMiddleware({ backend }),
      todoListMiddleware(),
      createSubAgentMiddleware({
        defaultModel: "anthropic:claude-sonnet-4-6",
        defaultTools: [],
        subagents: [
          {
            name: "researcher",
            description: "Searches and returns a structured summary.",
            systemPrompt:
              "Use the search tool to research the question and summarize key points.",
            tools: [search],
            model: "anthropic:claude-sonnet-5",
            middleware: [],
          },
        ],
      }),
    ],
  });
  ```

  ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, todoListMiddleware, tool } from "langchain";
  import {
    createFilesystemMiddleware,
    createSubAgentMiddleware,
    StateBackend,
  } from "deepagents";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var backend = new StateBackend();

  var agent = createAgent({
    model: "openrouter:z-ai/glm-5.2",
    tools: [search],
    middleware: [
      createFilesystemMiddleware({ backend }),
      todoListMiddleware(),
      createSubAgentMiddleware({
        defaultModel: "anthropic:claude-sonnet-4-6",
        defaultTools: [],
        subagents: [
          {
            name: "researcher",
            description: "Searches and returns a structured summary.",
            systemPrompt:
              "Use the search tool to research the question and summarize key points.",
            tools: [search],
            model: "openrouter:z-ai/glm-5.2",
            middleware: [],
          },
        ],
      }),
    ],
  });
  ```

  ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, todoListMiddleware, tool } from "langchain";
  import {
    createFilesystemMiddleware,
    createSubAgentMiddleware,
    StateBackend,
  } from "deepagents";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var backend = new StateBackend();

  var agent = createAgent({
    model: "fireworks:accounts/fireworks/models/glm-5p2",
    tools: [search],
    middleware: [
      createFilesystemMiddleware({ backend }),
      todoListMiddleware(),
      createSubAgentMiddleware({
        defaultModel: "anthropic:claude-sonnet-4-6",
        defaultTools: [],
        subagents: [
          {
            name: "researcher",
            description: "Searches and returns a structured summary.",
            systemPrompt:
              "Use the search tool to research the question and summarize key points.",
            tools: [search],
            model: "fireworks:accounts/fireworks/models/glm-5p2",
            middleware: [],
          },
        ],
      }),
    ],
  });
  ```

  ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, todoListMiddleware, tool } from "langchain";
  import {
    createFilesystemMiddleware,
    createSubAgentMiddleware,
    StateBackend,
  } from "deepagents";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var backend = new StateBackend();

  var agent = createAgent({
    model: "baseten:zai-org/GLM-5.2",
    tools: [search],
    middleware: [
      createFilesystemMiddleware({ backend }),
      todoListMiddleware(),
      createSubAgentMiddleware({
        defaultModel: "anthropic:claude-sonnet-4-6",
        defaultTools: [],
        subagents: [
          {
            name: "researcher",
            description: "Searches and returns a structured summary.",
            systemPrompt:
              "Use the search tool to research the question and summarize key points.",
            tools: [search],
            model: "baseten:zai-org/GLM-5.2",
            middleware: [],
          },
        ],
      }),
    ],
  });
  ```

  ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, todoListMiddleware, tool } from "langchain";
  import {
    createFilesystemMiddleware,
    createSubAgentMiddleware,
    StateBackend,
  } from "deepagents";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var backend = new StateBackend();

  var agent = createAgent({
    model: "ollama:north-mini-code-1.0",
    tools: [search],
    middleware: [
      createFilesystemMiddleware({ backend }),
      todoListMiddleware(),
      createSubAgentMiddleware({
        defaultModel: "anthropic:claude-sonnet-4-6",
        defaultTools: [],
        subagents: [
          {
            name: "researcher",
            description: "Searches and returns a structured summary.",
            systemPrompt:
              "Use the search tool to research the question and summarize key points.",
            tools: [search],
            model: "ollama:north-mini-code-1.0",
            middleware: [],
          },
        ],
      }),
    ],
  });
  ```
</CodeGroup>

See [Subagents](/oss/javascript/langchain/multi-agent/subagents).

<Note>
  This example imports from the `deepagents` package. Install it with:

  <CodeGroup>
    ```bash npm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    npm install deepagents
    ```

    ```bash yarn theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    yarn add deepagents
    ```

    ```bash pnpm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    pnpm add deepagents
    ```
  </CodeGroup>
</Note>

### Name your agent

Optionally use an identifier for the agent. This is especially useful when embedding the agent as a subgraph in [multi-agent](/oss/javascript/langchain/multi-agent) systems.

<CodeGroup>
  ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  var agent = createAgent({
    model: "google:gemini-3.6-flash",
    tools,
    name: "research_assistant",
  });
  ```

  ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  var agent = createAgent({
    model: "openai:gpt-5.5",
    tools,
    name: "research_assistant",
  });
  ```

  ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  var agent = createAgent({
    model: "anthropic:claude-sonnet-5",
    tools,
    name: "research_assistant",
  });
  ```

  ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  var agent = createAgent({
    model: "openrouter:z-ai/glm-5.2",
    tools,
    name: "research_assistant",
  });
  ```

  ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  var agent = createAgent({
    model: "fireworks:accounts/fireworks/models/glm-5p2",
    tools,
    name: "research_assistant",
  });
  ```

  ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  var agent = createAgent({
    model: "baseten:zai-org/GLM-5.2",
    tools,
    name: "research_assistant",
  });
  ```

  ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  var agent = createAgent({
    model: "ollama:north-mini-code-1.0",
    tools,
    name: "research_assistant",
  });
  ```
</CodeGroup>

### Fault tolerance

Agents in production encounter failures that rarely appear in development: rate limits, model timeouts, transient API errors. Fault tolerance middleware handles these at the infrastructure level so your tools and business logic don't need try/catch around every call.

<CodeGroup>
  ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import {
    createAgent,
    modelRetryMiddleware,
    tool,
    toolRetryMiddleware,
  } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "google:gemini-3.6-flash",
    tools: [search],
    middleware: [
      modelRetryMiddleware({ maxRetries: 3 }),
      toolRetryMiddleware({ maxRetries: 2 }),
    ],
  });
  ```

  ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import {
    createAgent,
    modelRetryMiddleware,
    tool,
    toolRetryMiddleware,
  } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "openai:gpt-5.5",
    tools: [search],
    middleware: [
      modelRetryMiddleware({ maxRetries: 3 }),
      toolRetryMiddleware({ maxRetries: 2 }),
    ],
  });
  ```

  ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import {
    createAgent,
    modelRetryMiddleware,
    tool,
    toolRetryMiddleware,
  } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "anthropic:claude-sonnet-5",
    tools: [search],
    middleware: [
      modelRetryMiddleware({ maxRetries: 3 }),
      toolRetryMiddleware({ maxRetries: 2 }),
    ],
  });
  ```

  ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import {
    createAgent,
    modelRetryMiddleware,
    tool,
    toolRetryMiddleware,
  } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "openrouter:z-ai/glm-5.2",
    tools: [search],
    middleware: [
      modelRetryMiddleware({ maxRetries: 3 }),
      toolRetryMiddleware({ maxRetries: 2 }),
    ],
  });
  ```

  ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import {
    createAgent,
    modelRetryMiddleware,
    tool,
    toolRetryMiddleware,
  } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "fireworks:accounts/fireworks/models/glm-5p2",
    tools: [search],
    middleware: [
      modelRetryMiddleware({ maxRetries: 3 }),
      toolRetryMiddleware({ maxRetries: 2 }),
    ],
  });
  ```

  ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import {
    createAgent,
    modelRetryMiddleware,
    tool,
    toolRetryMiddleware,
  } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "baseten:zai-org/GLM-5.2",
    tools: [search],
    middleware: [
      modelRetryMiddleware({ maxRetries: 3 }),
      toolRetryMiddleware({ maxRetries: 2 }),
    ],
  });
  ```

  ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import {
    createAgent,
    modelRetryMiddleware,
    tool,
    toolRetryMiddleware,
  } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "ollama:north-mini-code-1.0",
    tools: [search],
    middleware: [
      modelRetryMiddleware({ maxRetries: 3 }),
      toolRetryMiddleware({ maxRetries: 2 }),
    ],
  });
  ```
</CodeGroup>

See [`modelRetryMiddleware`](https://reference.langchain.com/javascript/langchain/index/modelRetryMiddleware), [`toolRetryMiddleware`](https://reference.langchain.com/javascript/langchain/index/toolRetryMiddleware), [Prebuilt middleware](/oss/javascript/langchain/middleware/built-in).

### Guardrails

Some policies can't live in a prompt—they need to be enforced deterministically regardless of what the model does. Guardrails intercept data as it flows through the agent loop, applying compliance rules or content policies before tool results reach the model's context.

<CodeGroup>
  ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, piiMiddleware, tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "google:gemini-3.6-flash",
    tools: [search],
    middleware: [piiMiddleware("email")],
  });
  ```

  ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, piiMiddleware, tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "openai:gpt-5.5",
    tools: [search],
    middleware: [piiMiddleware("email")],
  });
  ```

  ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, piiMiddleware, tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "anthropic:claude-sonnet-5",
    tools: [search],
    middleware: [piiMiddleware("email")],
  });
  ```

  ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, piiMiddleware, tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "openrouter:z-ai/glm-5.2",
    tools: [search],
    middleware: [piiMiddleware("email")],
  });
  ```

  ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, piiMiddleware, tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "fireworks:accounts/fireworks/models/glm-5p2",
    tools: [search],
    middleware: [piiMiddleware("email")],
  });
  ```

  ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, piiMiddleware, tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "baseten:zai-org/GLM-5.2",
    tools: [search],
    middleware: [piiMiddleware("email")],
  });
  ```

  ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, piiMiddleware, tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "ollama:north-mini-code-1.0",
    tools: [search],
    middleware: [piiMiddleware("email")],
  });
  ```
</CodeGroup>

See [`piiMiddleware`](https://reference.langchain.com/javascript/langchain/index/piiMiddleware), [Prebuilt middleware](/oss/javascript/langchain/middleware/built-in).

### Steering

Full autonomy isn't always appropriate. Steering lets you place humans at specific decision points—before destructive writes, expensive API calls, or anything requiring judgment—without restructuring your agent. The agent pauses and waits; a human approves, edits, or rejects; execution continues.

<CodeGroup>
  ```ts Google theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, humanInTheLoopMiddleware, tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "google:gemini-3.6-flash",
    tools: [search],
    middleware: [humanInTheLoopMiddleware({ interruptOn: { writeFile: true } })],
  });
  ```

  ```ts OpenAI theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, humanInTheLoopMiddleware, tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "openai:gpt-5.5",
    tools: [search],
    middleware: [humanInTheLoopMiddleware({ interruptOn: { writeFile: true } })],
  });
  ```

  ```ts Anthropic theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, humanInTheLoopMiddleware, tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "anthropic:claude-sonnet-5",
    tools: [search],
    middleware: [humanInTheLoopMiddleware({ interruptOn: { writeFile: true } })],
  });
  ```

  ```ts OpenRouter theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, humanInTheLoopMiddleware, tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "openrouter:z-ai/glm-5.2",
    tools: [search],
    middleware: [humanInTheLoopMiddleware({ interruptOn: { writeFile: true } })],
  });
  ```

  ```ts Fireworks theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, humanInTheLoopMiddleware, tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "fireworks:accounts/fireworks/models/glm-5p2",
    tools: [search],
    middleware: [humanInTheLoopMiddleware({ interruptOn: { writeFile: true } })],
  });
  ```

  ```ts Baseten theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, humanInTheLoopMiddleware, tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "baseten:zai-org/GLM-5.2",
    tools: [search],
    middleware: [humanInTheLoopMiddleware({ interruptOn: { writeFile: true } })],
  });
  ```

  ```ts Ollama theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { createAgent, humanInTheLoopMiddleware, tool } from "langchain";
  import * as z from "zod";

  var search = tool(({ query }) => `Search results for: ${query}`, {
    name: "search",
    description: "Search for a query and return a short summary.",
    schema: z.object({ query: z.string() }),
  });

  var agent = createAgent({
    model: "ollama:north-mini-code-1.0",
    tools: [search],
    middleware: [humanInTheLoopMiddleware({ interruptOn: { writeFile: true } })],
  });
  ```
</CodeGroup>

See [`humanInTheLoopMiddleware`](https://reference.langchain.com/javascript/langchain/middleware/humanInTheLoopMiddleware), [Human-in-the-loop](/oss/javascript/langchain/human-in-the-loop).

### Middleware resources

<CardGroup cols={3}>
  <Card title="Middleware overview" icon="route" href="/oss/javascript/langchain/middleware/overview" arrow>
    How the middleware stack works and when hooks fire
  </Card>

  <Card title="Prebuilt middleware" icon="package" href="/oss/javascript/langchain/middleware/built-in" arrow>
    Full reference with configuration examples
  </Card>

  <Card title="Custom middleware" icon="code" href="/oss/javascript/langchain/middleware/custom" arrow>
    Write your own hooks for business logic, PII scrubbing, and more
  </Card>
</CardGroup>

***

<div className="source-links">
  <Callout icon="terminal-2">
    [Connect these docs](/use-these-docs) to your agent of choice via MCP for real-time answers.
  </Callout>

  <Callout icon="edit">
    [Edit this page on GitHub](https://github.com/langchain-ai/docs/edit/main/src/oss/langchain/agents.mdx) or [file an issue](https://github.com/langchain-ai/docs/issues/new/choose).
  </Callout>
</div>
