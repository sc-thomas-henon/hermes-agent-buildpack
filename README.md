# Hermes Agent Buildpack for Scalingo

Custom [Scalingo](https://scalingo.com) buildpack that deploys
[Hermes Agent](https://github.com/NousResearch/hermes-agent) (Nous Research)
as a web application. Target stack: **scalingo-26** (Ubuntu 26.04 LTS), the
current default stack.

The buildpack follows the classic Scalingo/Heroku buildpack contract described
in [Use a Custom Buildpack](https://doc.scalingo.com/platform/deployment/buildpacks/custom):
`bin/detect`, `bin/compile`, `bin/release`, plus a `.profile.d` script written
into the app at build time.

## Usage

Set the `BUILDPACK_URL` environment variable on your Scalingo application:

```
scalingo --app my-app env-set BUILDPACK_URL=https://github.com/sc-thomas-henon/hermes-agent-buildpack
```

To test a branch instead of the default branch, append `#branch-name` to the
URL. Then push your application as usual.

## Detection

The buildpack applies when the application root contains:

- a `requirements.txt` or `pyproject.toml` mentioning `hermes-agent`
  (e.g. `hermes-agent @ git+https://github.com/NousResearch/hermes-agent.git@v0.23.4`), or
- a `Hermesfile` marker file.

## What the build does

`bin/compile`:

1. Installs system packages with apt: `git`, `ripgrep`, `ffmpeg`, `nodejs`,
   `python3.14` (+ venv/dev). Additional packages can be listed in an
   `Aptfile` at the app root (path overridable with `APT_FILE_MANIFEST`).
2. Creates a virtualenv in `/app/.venv` using the stack's Python 3.14
   (on stacks without it, a uv-managed Python 3.14 is installed into the
   build cache as a fallback).
3. Installs `hermes-agent` from a **pinned git tag** (`HERMES_AGENT_VERSION`).
   Upstream only supports source-checkout installs (its `setup.py` refuses to
   build wheels, and PyPI is stale), so the buildpack clones the tag, ships the
   checkout as `/app/hermes-src`, and installs it editable into the venv with
   `uv sync --frozen` against upstream's `uv.lock` (their `[tool.uv]`
   override-dependencies, e.g. Pillow, only apply in that mode). The clone is
   cached in the build cache and only re-fetched when the tag changes.
4. Installs the app's `requirements.txt` if present (`hermes-agent` lines are
   filtered out — the buildpack pins that version).
5. Writes `.profile.d/hermes.sh` which exports:
   - `PATH` with `/app/.venv/bin` first,
   - `HERMES_HOME` (default `/app/.hermes`),
   - `API_SERVER_HOST=0.0.0.0` and `API_SERVER_PORT=$PORT` so the gateway's
     API server listens on the port Scalingo expects.

`bin/release` declares the default process type:

```
web: hermes gateway run
```

Provide your own `Procfile` in the app to override it.

## Configuration variables

| Variable | Default | Description |
| --- | --- | --- |
| `HERMES_AGENT_VERSION` | `v0.23.4` (see `conf/versions.sh`) | Git tag of NousResearch/hermes-agent to install |
| `APT_FILE_MANIFEST` | `<app>/Aptfile` | Extra apt packages file |
| `BUILDPACK_DEBUG` | unset | Set to any value for `set -x` in compile |

Note: the Hermes source checkout (~330 MB) is shipped inside the app
(`/app/hermes-src`) because upstream does not publish installable wheels.

## Enabling the HTTP API on Scalingo

The gateway only starts its API server when it is enabled in the Hermes
config (`$HERMES_HOME/config.yaml`, i.e. `/app/.hermes/config.yaml` in the
app repo) with an access key:

```yaml
platforms:
  api_server:
    enabled: true
    extra:
      key: "change-me-at-least-16-chars"
```

The buildpack already points it at `0.0.0.0:$PORT` via `API_SERVER_HOST` /
`API_SERVER_PORT`. The API is then reachable on the application URL
(`/v1/chat/completions`, OpenAI-compatible).

## Local testing

Run the buildpack scripts in the same image Scalingo uses:

```
docker run --pull always --rm -it --env STACK=scalingo-26 \
  --volume /path/to/hermes-agent-buildpack:/buildpack \
  --volume /path/to/application:/build \
  scalingo/scalingo-26:latest bash

mkdir -p /tmp/cache /tmp/env
/buildpack/bin/detect /build
/buildpack/bin/compile /build /tmp/cache /tmp/env
/buildpack/bin/release /build
```

Or use the test harness (syntax + detect + release; `--compile` adds the full
build, needs root and network):

```
./test/run.sh           # fast checks
./test/run.sh --compile # full compile against test/fixture-app
```
