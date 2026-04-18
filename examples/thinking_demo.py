#!/usr/bin/env python3

import argparse
import json
from urllib import request


def chat(
    api_base: str,
    model: str,
    thinking: bool | None,
    max_tokens: int,
    thinking_token_budget: int | None,
) -> dict:
    payload = {
        "model": model,
        "messages": [
            {
                "role": "user",
                "content": "Solve 17 * 23. Give the final numeric answer clearly.",
            }
        ],
        "temperature": 0,
        "max_tokens": max_tokens,
    }

    if thinking is not None:
        payload["chat_template_kwargs"] = {"enable_thinking": thinking}

    if thinking_token_budget is not None:
        payload["thinking_token_budget"] = thinking_token_budget

    req = request.Request(
        f"{api_base.rstrip('/')}/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with request.urlopen(req, timeout=300) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Demo Gemma4 enable_thinking request control"
    )
    parser.add_argument("--api-base", default="http://127.0.0.1:8000")
    parser.add_argument("--model", default="gemma-4-26b-a4b-it-nvfp4a16")
    parser.add_argument("--max-tokens", type=int, default=512)
    parser.add_argument(
        "--thinking-token-budget",
        type=int,
        help="Optional vLLM cap for reasoning tokens; not a native Gemma4 reasoning level",
    )
    parser.add_argument(
        "--thinking",
        choices=["auto", "on", "off"],
        default="auto",
        help="Set Gemma4 chat_template_kwargs.enable_thinking for this request",
    )
    args = parser.parse_args()

    thinking = {"auto": None, "on": True, "off": False}[args.thinking]
    response = chat(
        args.api_base,
        args.model,
        thinking,
        args.max_tokens,
        args.thinking_token_budget,
    )
    message = response["choices"][0]["message"]

    print("thinking:", args.thinking)
    print(
        "reasoning:",
        json.dumps(message.get("reasoning"), ensure_ascii=False, indent=2),
    )
    print("content:", json.dumps(message.get("content"), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
