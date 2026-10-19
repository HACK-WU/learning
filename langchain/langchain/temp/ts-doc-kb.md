> ## Documentation Index
> Fetch the complete documentation index at: https://docs.langchain.com/llms.txt
> Use this file to discover all available pages before exploring further.

# Build a semantic search engine with LangChain

## Overview

Build a semantic search engine over a PDF with LangChain [embeddings](/oss/javascript/integrations/embeddings) and [vector stores](/oss/javascript/integrations/vectorstores). Use it to retrieve passages similar to a query, then plug the retriever into [retrieval-augmented generation (RAG)](/oss/javascript/deepagents/retrieval) or other LLM workflows.

This tutorial covers:

1. Create `Document` objects from a PDF.
2. Generate embeddings.
3. Load and split a PDF.
4. Index chunks in a vector store and query by similarity.
5. Wrap the store as a retriever.

The guide also includes a minimal RAG implementation on top of the search engine.

### Concepts

This tutorial focuses on text retrieval and covers the following concepts:

* [`Document`](https://reference.langchain.com/javascript/langchain-core/documents/Document)
* [Text splitters](/oss/javascript/integrations/splitters)
* [Embeddings](/oss/javascript/integrations/embeddings)
* [Vector stores](/oss/javascript/integrations/vectorstores) and [retrievers](/oss/javascript/integrations/retrievers)

## Setup

### Install dependencies

This tutorial reads a PDF using the `pdf-parse` package:

<CodeGroup>
  ```bash npm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  npm i pdf-parse
  ```

  ```bash yarn theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  yarn add pdf-parse
  ```

  ```bash pnpm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
  pnpm add pdf-parse
  ```
</CodeGroup>

For more details, see the [Installation guide](/oss/javascript/langchain/install).

### Configure LangSmith

Many of the applications you build with LangChain will contain multiple steps with multiple invocations of LLM calls.
As these applications get more and more complex, it becomes crucial to be able to inspect what exactly is going on inside your chain or agent.
The best way to do this is with [LangSmith](https://smith.langchain.com?utm_source=docs\&utm_medium=cta\&utm_campaign=langsmith-signup\&utm_content=oss-langchain-knowledge-base).

After you sign up at the link above, make sure to set your environment variables to start logging traces:

```shell theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
export LANGSMITH_TRACING="true"
export LANGSMITH_API_KEY="..."
```

## Create documents

LangChain implements a [`Document`](https://reference.langchain.com/javascript/langchain-core/documents/Document) abstraction for a unit of text and associated metadata. It has three attributes:

* `pageContent`: a string representing the content.
* `metadata`: a dict containing arbitrary metadata.
* `id`: (optional) a string identifier for the document.

`metadata` can capture the source of the document, its relationship to other documents, and other information. An individual [`Document`](https://reference.langchain.com/javascript/langchain-core/documents/Document) often represents a chunk of a larger document.

The following code creates sample documents:

```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
import { Document } from "@langchain/core/documents";

const documents = [
  new Document({
    pageContent:
      "Dogs are great companions, known for their loyalty and friendliness.",
    metadata: { source: "mammal-pets-doc" },
  }),
  new Document({
    pageContent: "Cats are independent pets that often enjoy their own space.",
    metadata: { source: "mammal-pets-doc" },
  }),
];
```

## Generate embeddings

Vector search stores numeric vectors associated with text. Embed a query as a vector of the same dimension, then use similarity metrics (such as cosine similarity) to find related text.

LangChain supports embeddings from [many providers](/oss/javascript/integrations/embeddings/). Select a model to specify how text should be converted into a numeric vector:

<Tabs>
  <Tab title="OpenAI">
    <CodeGroup>
      ```bash npm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      npm i @langchain/openai
      ```

      ```bash yarn theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      yarn add @langchain/openai
      ```

      ```bash pnpm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      pnpm add @langchain/openai
      ```
    </CodeGroup>

    ```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    import { OpenAIEmbeddings } from "@langchain/openai";

    const embeddings = new OpenAIEmbeddings({
      model: "text-embedding-3-large"
    });
    ```
  </Tab>

  <Tab title="Azure">
    <CodeGroup>
      ```bash npm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      npm i @langchain/openai
      ```

      ```bash yarn theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      yarn add @langchain/openai
      ```

      ```bash pnpm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      pnpm add @langchain/openai
      ```
    </CodeGroup>

    ```bash theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    AZURE_OPENAI_API_INSTANCE_NAME=<YOUR_INSTANCE_NAME>
    AZURE_OPENAI_API_KEY=<YOUR_KEY>
    AZURE_OPENAI_API_VERSION="2024-02-01"
    ```

    ```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    import { AzureOpenAIEmbeddings } from "@langchain/openai";

    const embeddings = new AzureOpenAIEmbeddings({
      azureOpenAIApiEmbeddingsDeploymentName: "text-embedding-ada-002"
    });
    ```
  </Tab>

  <Tab title="AWS">
    <CodeGroup>
      ```bash npm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      npm i @langchain/aws
      ```

      ```bash yarn theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      yarn add @langchain/aws
      ```

      ```bash pnpm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      pnpm add @langchain/aws
      ```
    </CodeGroup>

    ```bash theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    BEDROCK_AWS_REGION=your-region
    ```

    ```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    import { BedrockEmbeddings } from "@langchain/aws";

    const embeddings = new BedrockEmbeddings({
      model: "amazon.titan-embed-text-v1"
    });
    ```
  </Tab>

  <Tab title="Gemini Enterprise Agent Platform">
    <CodeGroup>
      ```bash npm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      npm i @langchain/google-vertexai
      ```

      ```bash yarn theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      yarn add @langchain/google-vertexai
      ```

      ```bash pnpm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      pnpm add @langchain/google-vertexai
      ```
    </CodeGroup>

    ```bash theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    GOOGLE_APPLICATION_CREDENTIALS=credentials.json
    ```

    ```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    import { VertexAIEmbeddings } from "@langchain/google-vertexai";

    const embeddings = new VertexAIEmbeddings({
      model: "gemini-embedding-001"
    });
    ```
  </Tab>

  <Tab title="MistralAI">
    <CodeGroup>
      ```bash npm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      npm i @langchain/mistralai
      ```

      ```bash yarn theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      yarn add @langchain/mistralai
      ```

      ```bash pnpm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      pnpm add @langchain/mistralai
      ```
    </CodeGroup>

    ```bash theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    MISTRAL_API_KEY=your-api-key
    ```

    ```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    import { MistralAIEmbeddings } from "@langchain/mistralai";

    const embeddings = new MistralAIEmbeddings({
      model: "mistral-embed"
    });
    ```
  </Tab>

  <Tab title="Cohere">
    <CodeGroup>
      ```bash npm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      npm i @langchain/cohere
      ```

      ```bash yarn theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      yarn add @langchain/cohere
      ```

      ```bash pnpm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      pnpm add @langchain/cohere
      ```
    </CodeGroup>

    ```bash theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    COHERE_API_KEY=your-api-key
    ```

    ```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    import { CohereEmbeddings } from "@langchain/cohere";

    const embeddings = new CohereEmbeddings({
      model: "embed-english-v3.0"
    });
    ```
  </Tab>
</Tabs>

```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
const vector1 = await embeddings.embedQuery(documents[0].pageContent);
const vector2 = await embeddings.embedQuery(documents[1].pageContent);

assert vector1.length === vector2.length;
console.log(`Generated vectors of length ${vector1.length}\n`);
console.log(vector1.slice(0, 10));
```

```text wrap theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
Generated vectors of length 1536

[-0.008586574345827103, -0.03341241180896759, -0.008936782367527485, -0.0036674530711025, 0.010564599186182022, 0.009598285891115665, -0.028587326407432556, -0.015824200585484505, 0.0030416189692914486, -0.012899317778646946]
```

Next, store embeddings in a vector store that supports efficient similarity search.

## Select a vector store

LangChain [`VectorStore`](https://reference.langchain.com/javascript/langchain-core/vectorstores/VectorStore) objects add text and [`Document`](https://reference.langchain.com/javascript/langchain-core/documents/Document) objects to a store and query them with similarity metrics. They are often initialized with [embedding](/oss/javascript/integrations/embeddings) models that translate text into numeric vectors.

LangChain includes [integrations](/oss/javascript/integrations/vectorstores) with many vector store technologies. Some are hosted and need credentials, some run in separate infrastructure (local or third-party), and others run in-memory for lightweight workloads. Select a vector store:

<Tabs>
  <Tab title="Memory">
    <CodeGroup>
      ```bash npm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      npm i @langchain/classic
      ```

      ```bash yarn theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      yarn add @langchain/classic
      ```

      ```bash pnpm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      pnpm add @langchain/classic
      ```
    </CodeGroup>

    ```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    import { MemoryVectorStore } from "@langchain/classic/vectorstores/memory";

    const vectorStore = new MemoryVectorStore(embeddings);
    ```
  </Tab>

  <Tab title="MongoDB">
    <CodeGroup>
      ```bash npm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      npm i @langchain/mongodb
      ```

      ```bash yarn theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      yarn add @langchain/mongodb
      ```

      ```bash pnpm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      pnpm add @langchain/mongodb
      ```
    </CodeGroup>

    ```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    import { MongoDBAtlasVectorSearch } from "@langchain/mongodb"
    import { MongoClient } from "mongodb";

    const client = new MongoClient(process.env.MONGODB_ATLAS_URI || "");
    const collection = client
      .db(process.env.MONGODB_ATLAS_DB_NAME)
      .collection(process.env.MONGODB_ATLAS_COLLECTION_NAME);

    const vectorStore = new MongoDBAtlasVectorSearch(embeddings, {
      collection: collection,
      indexName: "vector_index",
      textKey: "text",
      embeddingKey: "embedding",
    });
    ```
  </Tab>

  <Tab title="Pinecone">
    <CodeGroup>
      ```bash npm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      npm i @langchain/pinecone
      ```

      ```bash yarn theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      yarn add @langchain/pinecone
      ```

      ```bash pnpm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      pnpm add @langchain/pinecone
      ```
    </CodeGroup>

    ```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    import { PineconeStore } from "@langchain/pinecone";
    import { Pinecone as PineconeClient } from "@pinecone-database/pinecone";

    const pinecone = new PineconeClient({
      apiKey: process.env.PINECONE_API_KEY,
    });
    const pineconeIndex = pinecone.Index("your-index-name");

    const vectorStore = new PineconeStore(embeddings, {
      pineconeIndex,
      maxConcurrency: 5,
    });
    ```
  </Tab>

  <Tab title="Qdrant">
    <CodeGroup>
      ```bash npm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      npm i @langchain/qdrant
      ```

      ```bash yarn theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      yarn add @langchain/qdrant
      ```

      ```bash pnpm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      pnpm add @langchain/qdrant
      ```
    </CodeGroup>

    ```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    import { QdrantVectorStore } from "@langchain/qdrant";

    const vectorStore = await QdrantVectorStore.fromExistingCollection(embeddings, {
      url: process.env.QDRANT_URL,
      collectionName: "langchainjs-testing",
    });
    ```
  </Tab>

  <Tab title="Redis">
    <CodeGroup>
      ```bash npm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      npm i @langchain/redis
      ```

      ```bash yarn theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      yarn add @langchain/redis
      ```

      ```bash pnpm theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
      pnpm add @langchain/redis
      ```
    </CodeGroup>

    ```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
    import { RedisVectorStore } from "@langchain/redis";

    const vectorStore = new RedisVectorStore(embeddings, {
      redisClient: client,
      indexName: "langchainjs-testing",
    });
    ```
  </Tab>
</Tabs>

## Load and split a PDF

Load content from a PDF, then split it into smaller chunks before indexing. This example uses [a sample Nike 10-K filing from 2023](https://github.com/langchain-ai/langchain/blob/v0.3/docs/docs/example_data/nke-10k-2023.pdf).

```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
import { readFileSync } from "node:fs";
import { Document } from "@langchain/core/documents";
import { PDFParse } from "pdf-parse";

// Below is a minimal helper for demonstration purposes.
async function loadPdfPages(filePath: string): Promise<Document[]> {
  const parser = new PDFParse({
    data: new Uint8Array(readFileSync(filePath)),
  });
  try {
    const { pages } = await parser.getText();
    return pages.map(
      (page) =>
        new Document({
          pageContent: page.text,
          metadata: { source: filePath, page: page.num - 1 },
        })
    );
  } finally {
    await parser.destroy();
  }
}

const filePath = "../../data/nke-10k-2023.pdf";
const docs = await loadPdfPages(filePath);
console.log(docs.length);
```

```text theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
107
```

A page is often too coarse for retrieval. Split pages further so relevant passages are not diluted by surrounding text. [`RecursiveCharacterTextSplitter`](https://reference.langchain.com/javascript/langchain-textsplitters/RecursiveCharacterTextSplitter) recursively splits on common separators (such as newlines) until each chunk is the target size. This is the recommended text splitter for generic text use cases.

```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
import { RecursiveCharacterTextSplitter } from "@langchain/textsplitters";

const textSplitter = new RecursiveCharacterTextSplitter({
  chunkSize: 1000,
  chunkOverlap: 200,
});

const allSplits = await textSplitter.splitDocuments(docs);

console.log(allSplits.length);
```

```text theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
516
```

## Index documents

Index the chunks into the vector store:

```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
await vectorStore.addDocuments(allSplits);
```

Most vector store integrations also support connecting to an existing store (for example with a client or index name). See the docs for a specific [integration](/oss/javascript/integrations/vectorstores) for details.

## Query the vector store

After you have added the documents to the [`VectorStore`](https://reference.langchain.com/javascript/langchain-core/vectorstores/VectorStore), you can query it:

* Synchronously and asynchronously
* By string query and by vector
* With and without similarity scores
* By similarity and [maximum marginal relevance](https://reference.langchain.com/javascript/classes/_langchain_core.vectorstores.VectorStore.html#maxMarginalRelevanceSearch) (to balance similarity with diversity)

These methods generally return a list of [`Document`](https://reference.langchain.com/javascript/langchain-core/documents/Document) objects.

### Search by string

Embeddings map text to dense vectors so similar meanings are geometrically close. This means you can Retrieve relevant passages by passing a natural-language question:

```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
const results1 = await vectorStore.similaritySearch(
  "When was Nike incorporated?"
);

console.log(results1[0]);
```

```javascript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
Document {
    pageContent: 'direct to consumer operations sell products...',
    metadata: {'page': 4, 'source': '../example_data/nke-10k-2023.pdf', 'start_index': 3125}
}
```

### Return scores

You can return similarity scores with the documents. Score meaning varies by provider. In this case, the score is a distance metric that varies inversely with similarity:

```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
const results2 = await vectorStore.similaritySearchWithScore(
  "What was Nike's revenue in 2023?"
);

console.log(results2[0]);
```

```javascript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
Score: 0.23699893057346344

Document {
    pageContent: 'Table of Contents...',
    metadata: {'page': 35, 'source': '../example_data/nke-10k-2023.pdf', 'start_index': 0}
}
```

### Search by vector

Embed the query yourself, then search with the resulting vector:

```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
const embedding = await embeddings.embedQuery(
  "How were Nike's margins impacted in 2023?"
);

const results3 = await vectorStore.similaritySearchVectorWithScore(
  embedding,
  1
);

console.log(results3[0]);
```

```javascript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
Document {
    pageContent: 'FISCAL 2023 COMPARED TO FISCAL 2022...',
    metadata: {
        'page': 36,
        'source': '../example_data/nke-10k-2023.pdf',
        'start_index': 0
    }
}
```

Learn more:

* [API Reference](https://reference.langchain.com/javascript/langchain-core/vectorstores/VectorStore)
* [Integration-specific docs](/oss/javascript/integrations/vectorstores)

## Use retrievers

LangChain [`VectorStore`](https://reference.langchain.com/javascript/langchain-core/vectorstores/VectorStore) objects do not subclass [`Runnable`](https://reference.langchain.com/javascript/langchain-core/runnables/Runnable). [Retrievers](https://reference.langchain.com/javascript/interfaces/_langchain_core.retrievers.BaseRetriever.html) are Runnables, so they support standard methods such as sync and async `invoke` and `batch`.

You can also build retrievers from vector stores, and retrievers can also wrap non-vector sources (such as external APIs).

Vector stores implement an `as_retriever` method that returns a [`VectorStoreRetriever`](https://reference.langchain.com/python/langchain-core/vectorstores/base/VectorStoreRetriever). These retrievers expose `search_type` and `search_kwargs` to select and parameterize the underlying store methods. Replicate the example above with:

```typescript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
const retriever = vectorStore.asRetriever({
  searchType: "mmr",
  searchKwargs: {
    fetchK: 1,
  },
});

await retriever.batch([
  "When was Nike incorporated?",
  "What was Nike's revenue in 2023?",
]);
```

```javascript theme={"theme":{"light":"catppuccin-latte","dark":"catppuccin-mocha"}}
[
    [Document {
        metadata: {'page': 4, 'source': '../example_data/nke-10k-2023.pdf', 'start_index': 3125},
        pageContent: 'direct to consumer operations sell products...',
    }],
    [Document {
        metadata: {'page': 3, 'source': '../example_data/nke-10k-2023.pdf', 'start_index': 0},
        pageContent: 'Table of Contents...',
    }],
]
```

You can use retrievers in more complex apps such as [retrieval-augmented generation (RAG)](/oss/javascript/deepagents/retrieval), which combine a question with retrieved context in a prompt for an LLM. To learn more about building such an application, check out the [RAG tutorial](/oss/javascript/deepagents/rag) tutorial.

## Next steps

You've now seen how to build a semantic search engine over a PDF document.

For more information see:

* [Available embedding integrations](/oss/javascript/integrations/embeddings)
* [Available vector store integrations](/oss/javascript/integrations/vectorstores)

For more on RAG:

* [Retrieval overview](/oss/javascript/deepagents/retrieval)
* [RAG with Deep Agents](/oss/javascript/deepagents/rag)
* [Evaluate a RAG application](/langsmith/evaluate-rag-tutorial)

***

<div className="source-links">
  <Callout icon="terminal-2">
    [Connect these docs](/use-these-docs) to your agent of choice via MCP for real-time answers.
  </Callout>

  <Callout icon="edit">
    [Edit this page on GitHub](https://github.com/langchain-ai/docs/edit/main/src/oss/langchain/knowledge-base.mdx) or [file an issue](https://github.com/langchain-ai/docs/issues/new/choose).
  </Callout>
</div>
