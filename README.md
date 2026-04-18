# GB10 Gemma4 Playbook

Customer-ready playbook for serving `bg-digitalservices/Gemma-4-26B-A4B-it-NVFP4A16` on a single NVIDIA GB10 / DGX Spark with vLLM.

This repo wraps the underlying `spark-vllm-docker` deployment code as a git submodule and adds the bootstrap, lifecycle, and benchmark scripts needed to hand the workflow to another operator with minimal context.

## Scope

- Single-node only.
- Full `262144` token context length.
- NVFP4 checkpoint with the required Gemma4 loader patch.
- Gemma4 tool-calling patch and reasoning parser enabled.
- Reproducible benchmark report generation in Markdown.

This playbook intentionally does not deploy a two-node GB10 topology for this model. A 26B NVFP4 MoE model does not materially benefit from that topology for this use case, and the current distributed NVFP4 MoE backends fail on GB10.

## What The Bootstrap Does

`./scripts/bootstrap.sh` performs the full first-time setup on the target GB10:

1. Verifies SSH access to the target host.
2. Syncs the pinned `spark-vllm-docker` submodule to the target host.
3. Installs `uv` on the target host if it is missing.
4. Builds the `vllm-node-tf5` image.
5. Downloads `bg-digitalservices/Gemma-4-26B-A4B-it-NVFP4A16`.
6. Launches the single-node `gemma4-26b-a4b-nvfp4a16` recipe.
7. Waits for the OpenAI-compatible API to report healthy.

## Prerequisites

On the operator machine:

- `git`
- `ssh`
- `rsync`
- `curl`
- `python3` for optional example clients
- `uv` for the local example virtual environment

On the target GB10:

- SSH access as `dell` or another sudo-capable user
- NVIDIA drivers and Docker already installed
- Outbound internet access to GitHub and Hugging Face

## Quick Start

Clone the repo with submodules:

```bash
git clone --recurse-submodules https://github.com/spencerbull/gb10-gemma4-playbook.git
cd gb10-gemma4-playbook
```

Create the deployment config:

```bash
cp .env.example .env
```

Edit `.env` and set at least:

```bash
TARGET_HOST=<your-gb10-hostname-or-ip>
TARGET_USER=dell
```

Optional: choose the server-wide default thinking mode:

```bash
GEMMA4_THINKING_DEFAULT=auto
```

Allowed values:

- `auto`: keep the model default
- `on`: default all requests to `enable_thinking=true`
- `off`: default all requests to `enable_thinking=false`

Run the full bootstrap:

```bash
./bootstrap.sh
```

Verify the service:

```bash
./status.sh
```

Run the benchmark suite and pull the Markdown report back locally:

```bash
./benchmark.sh
```

Stop the service when you are done:

```bash
./stop.sh
```

## Day 2 Operations

Restart the model without rebuilding or redownloading:

```bash
./start.sh
```

Rerun bootstrap but skip the expensive steps:

```bash
./bootstrap.sh --skip-build --skip-download
```

Use the `Makefile` if you prefer shorter commands:

```bash
make bootstrap
make status
make benchmark
make stop
```

Top-level bash wrappers are also provided for the main operations:

```bash
./bootstrap.sh
./start.sh
./status.sh
./benchmark.sh
./stop.sh
```

## Tool Calling And Reasoning

The bundled Gemma4 NVFP4 recipe starts vLLM with:

- `mods/fix-gemma4-tool-parser`
- `mods/fix-gemma4-nvfp4`
- `--enable-auto-tool-choice`
- `--tool-call-parser gemma4`
- `--reasoning-parser gemma4`

That means the server is ready for both:

- OpenAI-style tool calling
- Gemma4 reasoning extraction via the `reasoning` field in chat completions

### Native Gemma4 Thinking Control

For this checkpoint, the native Gemma4 chat template exposes a boolean `enable_thinking` control. I did not find low/medium/high reasoning levels in the shipped chat template or tokenizer config for this model.

You can control thinking per request with `chat_template_kwargs.enable_thinking`:

Reasoning on:

```json
{
  "chat_template_kwargs": {
    "enable_thinking": true
  }
}
```

Reasoning off:

```json
{
  "chat_template_kwargs": {
    "enable_thinking": false
  }
}
```

If you are using the OpenAI Python client, pass the same object through `extra_body={...}` because that client lifts it into the top-level request body for you.

If you want a server-wide default instead, set `GEMMA4_THINKING_DEFAULT=on` or `off` in `.env` before running `bootstrap.sh` or `start.sh`.

### Optional vLLM Thinking Budget

`thinking_token_budget` is not a Gemma4-native reasoning level. It is a generic vLLM control that can cap how many tokens the model spends in the reasoning channel before it is forced to answer.

This is optional and only useful if you want to keep long reasoning traces from consuming the entire response budget.

### Example Clients

The example clients use the OpenAI Python SDK:

```bash
./setup-python.sh
```

These examples intentionally use the SDK because the service is OpenAI-compatible and that is the client most customers will integrate with. They keep the response as an OpenAI SDK object all the way through the example instead of dropping back to raw HTTP payloads. The benchmark utility still uses raw HTTP because it also depends on vLLM's non-OpenAI `/tokenize` endpoint and measures lower-level streaming details directly.

Thinking toggle demo:

```bash
./thinking-demo.sh --api-base http://<host>:8000 --thinking on --max-tokens 512
./thinking-demo.sh --api-base http://<host>:8000 --thinking off
```

If you want to cap the reasoning channel explicitly, set a thinking budget:

```bash
./thinking-demo.sh --api-base http://<host>:8000 --thinking on --thinking-token-budget 128
```

Tool-calling demo:

```bash
./tool-call-demo.sh --api-base http://<host>:8000
```

## Reference Performance

Observed on a single GB10 with the bundled benchmark script and `256` completion tokens:

| Case | Runs | Avg prompt toks | Avg completion toks | Avg TTFT s | Avg total s | Avg prefill tok/s | Avg decode tok/s | Avg output tok/s | Avg total tok/s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| small-prompt | 2 | 40.00 | 256.00 | 0.06 | 5.03 | 770.83 | 51.55 | 50.93 | 58.89 |
| large-prompt | 2 | 240,013.00 | 256.00 | 461.23 | 469.35 | 520.39 | 31.56 | 0.55 | 511.94 |

Notes:

- Small prompts are decode-bound on this setup.
- Near-limit prompts are dominated by prefill cost.
- `./scripts/benchmark.sh` writes fresh reports to `reports/` on the operator machine.

## Repo Layout

```text
.
├── .env.example
├── Makefile
├── README.md
├── benchmark.sh
├── bootstrap.sh
├── examples/
├── reports/
├── scripts/
├── setup-python.sh
├── start.sh
├── status.sh
├── stop.sh
├── thinking-demo.sh
├── tool-call-demo.sh
└── spark-vllm-docker/
```

- top-level `*.sh` files are the main customer entrypoints.
- `scripts/` contains the implementation behind those wrappers.
- `examples/` contains request examples for tool calling and Gemma4 thinking control.
- `spark-vllm-docker/` is a pinned submodule to the deployment code fork.
- `reports/` is where benchmark Markdown files are written locally.

## Update Workflow

When the underlying Spark deployment code changes, update the submodule and commit the new pointer:

```bash
git submodule update --remote --merge spark-vllm-docker
git add spark-vllm-docker .gitmodules
git commit -m "Update spark-vllm-docker submodule"
```

## Troubleshooting

API not coming up:

```bash
./scripts/status.sh
ssh dell@<target-host> "docker logs vllm_node | tail -n 200"
```

Rebuild from scratch:

```bash
./scripts/stop.sh
./scripts/bootstrap.sh
```

Model benchmark report location:

```bash
ls -1 reports/
```
