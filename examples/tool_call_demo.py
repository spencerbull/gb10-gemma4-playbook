#!/usr/bin/env python3

import argparse
import json
from urllib import request


TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "Get the current weather for a city",
            "parameters": {
                "type": "object",
                "properties": {
                    "location": {"type": "string"},
                    "unit": {
                        "type": "string",
                        "enum": ["celsius", "fahrenheit"],
                    },
                },
                "required": ["location", "unit"],
            },
        },
    }
]


def chat(api_base: str, model: str) -> dict:
    payload = {
        "model": model,
        "messages": [
            {
                "role": "user",
                "content": "What is the weather in Austin, Texas? Use the tool if needed.",
            }
        ],
        "tools": TOOLS,
        "tool_choice": "auto",
        "temperature": 0,
        "max_tokens": 256,
    }

    req = request.Request(
        f"{api_base.rstrip('/')}/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with request.urlopen(req, timeout=300) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description="Demo Gemma4 tool calling")
    parser.add_argument("--api-base", default="http://127.0.0.1:8000")
    parser.add_argument("--model", default="gemma-4-26b-a4b-it-nvfp4a16")
    args = parser.parse_args()

    response = chat(args.api_base, args.model)
    message = response["choices"][0]["message"]
    print(json.dumps(message, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
