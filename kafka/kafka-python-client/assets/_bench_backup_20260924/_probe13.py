import importlib
for m in ["confluent_kafka","fastapi","uvicorn","prometheus_client",
          "aiokafka","kafka","pydantic","jsonschema","httpx","pytest"]:
    try:
        mod = importlib.import_module(m)
        print(f"  {m:20} {getattr(mod,'__version__','?')}")
    except Exception as e:
        print(f"  {m:20} MISSING ({type(e).__name__})")
