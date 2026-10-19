> ## Documentation Index
> Fetch the complete documentation index at: https://docs.langchain.com/llms.txt
> Use this file to discover all available pages before exploring further.

# Model Context Protocol (MCP)

> Connect LangChain agents to MCP servers with MCPAdapter.

[Model Context Protocol (MCP)](https://modelcontextprotocol.io) is an open protocol that standardizes how applications provide tools and context to language models. LangChain agents call tools defined on MCP servers through [`MCPAdapter`](https://reference.langchain.com/javascript/langchain-mcp-adapters/MCPAdapter), which discovers a server's tools and adapts them into LangChain tools you can pass straight to [`createAgent`](https://reference.langchain.com/javascript/langchain/index/createAgent).

<Note>
  This guide requires `@langchain/mcp-adapters` 2.0 or later. If you use 1.x, see the [1.x docs](/oss/javascript/langchain/mcp-v1) or the [migration guide](/oss/javascript/migrate/langchain-mcp-adapters).
</Note>

## Install

Install the `@langchain/mcp-adapters` package and its peer dependencies:

<CodeGroup>
  ```bash npm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  npm install @langchain/mcp-adapters@^2.0.0 @langchain/core @langchain/langgraph
  ```

  ```bash pnpm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  pnpm add @langchain/mcp-adapters@^2.0.0 @langchain/core @langchain/langgraph
  ```

  ```bash yarn theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  yarn add @langchain/mcp-adapters@^2.0.0 @langchain/core @langchain/langgraph
  ```

  ```bash bun theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  bun add @langchain/mcp-adapters@^2.0.0 @langchain/core @langchain/langgraph
  ```
</CodeGroup>

Add `@modelcontextprotocol/client` too if you import SDK types or transports.

## Quickstart

Connect an agent to the [LangChain docs MCP server](/use-these-docs) to search the documentation. This example requires `langchain`, `@langchain/anthropic`, and an Anthropic API key. See the [LangChain quickstart](/oss/javascript/langchain/quickstart) for setup.

Keep the adapter open while the agent runs, then close it in `finally`:

```ts theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
import { MCPAdapter } from "@langchain/mcp-adapters";
import { createAgent } from "langchain";

async function main() {
  const adapter = new MCPAdapter({
    servers: { docs: { url: "https://docs.langchain.com/mcp" } },
  });

  try {
    const tools = await adapter.listTools();
    const agent = createAgent({ model: "claude-sonnet-5", tools });
    const result = await agent.invoke({
      messages: [
        {
          role: "user",
          content: "How do I add short-term memory to a LangChain agent?",
        },
      ],
    });
    console.log(result.messages.at(-1)?.text);
  } finally {
    await adapter.close();
  }
}

await main();
```

<Card title="View example trace" icon="chart-line" href="https://smith.langchain.com/public/871aa85b-f22e-430a-ab74-5c9669203282/r" arrow horizontal>
  Open a public LangSmith run for this example.
</Card>

<Accordion title="LangChain docs MCP server">
  The [LangChain docs MCP server](/use-these-docs) is a public HTTP endpoint at `https://docs.langchain.com/mcp`.

  Connect an agent to it to search and read documentation without writing custom tools:

  ```ts theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  import { MCPAdapter } from "@langchain/mcp-adapters";
  import { createAgent } from "langchain";

  async function main() {
    const adapter = new MCPAdapter({
      servers: { docs: { url: "https://docs.langchain.com/mcp" } }, // [!code highlight]
    });

    try {
      const tools = await adapter.listTools();
      const agent = createAgent({ model: "claude-sonnet-5", tools });
      return await agent.invoke({
        messages: [
          {
            role: "user",
            content: "How do I add short-term memory to a LangChain agent?",
          },
        ],
      });
    } finally {
      await adapter.close();
    }
  }
  ```

  <Card title="View example trace" icon="chart-line" href="https://smith.langchain.com/public/e5a365b0-d712-46ca-ab53-61cb0e4e1acd/r" arrow horizontal>
    Open a public LangSmith run for this example.
  </Card>

  <Note>
    The docs MCP server is public and does not require an API key. For IDE and coding-agent setup (Claude Code, Cursor, and others), see [Use docs programmatically](/use-these-docs).
  </Note>

  The server exposes these tools:

  | Tool | Description |
  | - | - |
  | `search_docs_by_lang_chain` | Search docs for relevant guides, how-tos, and examples. |
  | `query_docs_filesystem_docs_by_lang_chain` | Read or search docs through a virtual filesystem (`rg`, `head`, `cat`, and related commands). |
  | `submit_feedback` | Report a problem with a documentation page. |

  `MCPAdapter` exposes these tools with the server-name prefix, for example `docs_search_docs_by_lang_chain`.
</Accordion>

## Transports

[`MCPAdapter`](https://reference.langchain.com/javascript/langchain-mcp-adapters/MCPAdapter) accepts a map of named server definitions. It selects the transport from each definition, so one adapter can connect to local stdio servers and remote HTTP servers at the same time:

```ts theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
import { MCPAdapter } from "@langchain/mcp-adapters";

const adapter = new MCPAdapter({
  servers: {
    // A local server launched as a subprocess over stdio.
    local: {
      command: "node",
      args: ["./weather-server.js"],
    },

    // A remote server reached over Streamable HTTP.
    remote: {
      url: "https://example.com/mcp",
    },

    // A legacy server with an explicit SSE endpoint.
    legacy: {
      url: "https://legacy.example.com/sse",
      transport: "sse",
      mode: "legacy",
    },
  },
});

try {
  const tools = await adapter.listTools();
  // Pass tools to createAgent({ tools, ... }).
} finally {
  await adapter.close();
}
```

<Card title="View example trace" icon="chart-line" href="https://smith.langchain.com/public/d9a802f7-75cf-45b4-b0f6-f4a62fa06e27/r" arrow horizontal>
  Open a public LangSmith run for this example.
</Card>

Each server definition can use one of these transports:

* **stdio**: Provide `command` and `args`. The adapter starts the command as a child process and communicates over standard input and output.
* **Streamable HTTP**: Provide `url`. This is the default transport for URL-based servers, so `transport: "http"` is optional.
* **SSE**: Provide `url` and set `transport: "sse"`. Use this transport only for legacy servers that expose an SSE endpoint.

Transport selection and protocol negotiation are separate. The optional `mode` setting controls which MCP protocol era the client accepts. See [Protocol eras](/oss/javascript/langchain/mcp/connections#protocol-eras).

<Note>
  For new remote servers, omit both `transport` and `mode`. The adapter uses Streamable HTTP with automatic protocol negotiation. Specify these settings only when connecting to a server with known legacy requirements.
</Note>

## Next steps

<CardGroup cols={2}>
  <Card title="Tools" icon="tool" href="/oss/javascript/langchain/mcp/tools">
    Load MCP tools into agents, control their execution, and handle their outputs.
  </Card>

  <Card title="Connections" icon="plug" href="/oss/javascript/langchain/mcp/connections">
    Connection lifecycle, multiple servers, protocol eras, and caching.
  </Card>

  <Card title="Authentication" icon="lock" href="/oss/javascript/langchain/mcp/auth">
    Bearer tokens, OAuth 2.1, and per-user server auth.
  </Card>
</CardGroup>

***

<div className="source-links">
  <Callout icon="terminal-2">
    [Connect these docs](/use-these-docs) to your agent of choice via MCP for real-time answers.
  </Callout>

  <Callout icon="edit">
    [Edit this page on GitHub](https://github.com/langchain-ai/docs/edit/main/src/oss/langchain/mcp/index.mdx) or [file an issue](https://github.com/langchain-ai/docs/issues/new/choose).
  </Callout>
</div>
