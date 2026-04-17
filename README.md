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
- `python3`

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

Optional: choose the server-wide default reasoning mode:

```bash
GEMMA4_REASONING_MODE=auto
```

Allowed values:

- `auto`: keep the model default
- `on`: default all requests to `enable_thinking=true`
- `off`: default all requests to `enable_thinking=false`

Run the full bootstrap:

```bash
./scripts/bootstrap.sh
```

Verify the service:

```bash
./scripts/status.sh
```

Run the benchmark suite and pull the Markdown report back locally:

```bash
./scripts/benchmark.sh
```

Stop the service when you are done:

```bash
./scripts/stop.sh
```

## Day 2 Operations

Restart the model without rebuilding or redownloading:

```bash
./scripts/start.sh
```

Rerun bootstrap but skip the expensive steps:

```bash
./scripts/bootstrap.sh --skip-build --skip-download
```

Use the `Makefile` if you prefer shorter commands:

```bash
make bootstrap
make status
make benchmark
make stop
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

### Request-Level Reasoning Modes

You can control reasoning per request with `chat_template_kwargs.enable_thinking`:

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

If you want a server-wide default instead, set `GEMMA4_REASONING_MODE=on` or `off` in `.env` before running `bootstrap.sh` or `start.sh`.

### Example Clients

Reasoning mode demo:

```bash
python3 examples/reasoning_modes.py --api-base http://<host>:8000 --mode on --max-tokens 512
python3 examples/reasoning_modes.py --api-base http://<host>:8000 --mode off
```

If you want to cap the reasoning channel explicitly, set a thinking budget:

```bash
python3 examples/reasoning_modes.py --api-base http://<host>:8000 --mode on --thinking-token-budget 128
```

Tool-calling demo:

```bash
python3 examples/tool_call_demo.py --api-base http://<host>:8000
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
├── examples/
├── reports/
├── scripts/
└── spark-vllm-docker/
```

- `scripts/` contains the customer-facing wrapper commands.
- `examples/` contains request examples for tool calling and reasoning modes.
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
