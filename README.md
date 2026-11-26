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

1. Fetches system packages (`ripgrep`, `ffmpeg`, `nodejs`) the Scalingo way:
   `bin/compile` runs as a non-root user, so instead of `apt-get install` it
   downloads the .debs with `apt-get -d` (apt state/cache redirected into the
   build cache) and extracts them with `dpkg -x` into `/app/.apt`, exposed at
   runtime via `.profile.d/000_apt.sh`. Extra packages can be listed in an
   `Aptfile` at the app root (path overridable with `APT_FILE_MANIFEST`).
   `python3.14` itself comes from the scalingo-26 base image.
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
| `HERMES_UV_EXTRAS` | unset | Space-separated uv extras installed from upstream's `uv.lock` at compile time (e.g. `messaging edge-tts` for Telegram/Discord bots + voice, `voice` for local faster-whisper STT) |
| `HERMES_STT_PROVIDER` | unset | Baked into `/app/.hermes/config.yaml` as `stt.provider` (`local` \| `groq` \| `openai` \| …) |
| `HERMES_STT_LANGUAGE` | unset | Baked as `stt.language` (e.g. `fr`) |
| `HERMES_TTS_PROVIDER` | unset | Baked as `tts.provider` (`edge` \| `elevenlabs` \| `openai` \| …) |
| `HERMES_TTS_VOICE` | unset | Baked as `tts.edge.voice` (e.g. `fr-FR-DeniseNeural`) |
| `HERMES_VOICE_AUTO_TTS` / `HERMES_VOICE_AUTO_TTS_MODE` | unset | Baked as `voice.auto_tts` / `voice.auto_tts_mode` (gateway voice replies) |

`HERMES_STT_*`/`HERMES_TTS_*`/`HERMES_VOICE_*` are compile-time only (they generate
the baked `config.yaml`, since the container fs is ephemeral and these keys have
no env mapping upstream). Secrets never go in `config.yaml`: any `*_API_KEY`,
`*_BOT_TOKEN` and `VOICE_TOOLS_OPENAI_KEY` app env var is bridged into
`$HERMES_HOME/.env` (0600) at container boot by `.profile.d/hermes.sh`.

## Voice (Discord voice channels, Telegram/Discord voice notes)

`libopus0` is installed for the Discord Opus codec and `ffmpeg` for audio
conversion. To run a Discord bot with voice channels on the `hermes gateway run`
app:

1. Create a bot at <https://discord.com/developers/applications> (Bot → token),
   enable the **Presence, Server Members and Message Content** privileged intents,
   and invite it with the OAuth2 URL generated with scopes `bot applications.commands`
   and permissions `309240908864` (text + Connect/Speak).
2. Set app env vars: `DISCORD_BOT_TOKEN`, `DISCORD_ALLOWED_USERS=<your numeric
   user id>` (Developer Mode → right-click your name → Copy ID), plus
   `HERMES_UV_EXTRAS="messaging edge-tts"` (rebuild needed — extras are compile-time).
3. STT: `GROQ_API_KEY` + `HERMES_STT_PROVIDER=groq` (fast, free tier), or add
   `voice` to `HERMES_UV_EXTRAS` for local faster-whisper (no key, downloads the
   model from Hugging Face on first use). TTS: `edge` (default, free) or
   `ELEVENLABS_API_KEY` + `HERMES_TTS_PROVIDER=elevenlabs`.
4. Redeploy, join a voice channel in Discord and send `/voice join` in a text
   channel (DMs need no mention; server channels require @bot by default).

Note: the Hermes source checkout (~330 MB) is shipped inside the app
(`/app/hermes-src`) because upstream does not publish installable wheels.

## Enabling the HTTP API on Scalingo (via environment variables)

No `config.yaml` is needed: Hermes enables the `api_server` platform from the
environment alone (`gateway/config_env.py` in hermes-agent). Set these as
Scalingo config vars on the app (`scalingo env-set` or `POST /v1/apps/:app/variables`):

| Variable | Example | Effect |
| --- | --- | --- |
| `API_SERVER_KEY` | `scalingo env-set API_SERVER_KEY=$(openssl rand -hex 16)` | Enables the API server (key must be ≥ 16 chars) and is the Bearer token |
| `API_SERVER_HOST` | `0.0.0.0` | Bind address (buildpack default) |
| `API_SERVER_PORT` | `$PORT` | Bind port (buildpack maps Scalingo's `$PORT` by default) |
| `API_SERVER_CORS_ORIGINS` | `https://example.com` | Optional CORS origins (CSV) |
| `API_SERVER_MODEL_NAME` | `hermes-agent` | Optional model name override |

The buildpack's `.profile.d/hermes.sh` provides the `0.0.0.0` / `$PORT`
defaults, and app config vars override them. The API is then reachable on the
application URL: `GET /v1/models`, `POST /v1/chat/completions`, … with
`Authorization: Bearer $API_SERVER_KEY`. A plain `config.yaml` in
`$HERMES_HOME` still works too and is merged underneath the env overrides.

Provider API keys set as app config vars (any `*_API_KEY`, e.g.
`OPENROUTER_API_KEY`) are bridged at container boot into `$HERMES_HOME/.env`
(mode 0600) by `.profile.d/hermes.sh`: the gateway resolves provider
credentials through the profile secret scope (`<home>/.env`) and, under
multiplexing, a scope miss never falls back to `os.environ` — the env var
alone would stay invisible to the model runtime.

## Deploying an app with this buildpack

- Set `BUILDPACK_URL` on the Scalingo app (optionally `#branch` to pin a
  branch). With the Scalingo API, archive deploys (`POST /v1/sources`, PUT the
  tar.gz, then `POST /v1/apps/:app/deployments` with `source_url`) require the
  tar to contain a **single top-level folder** with the app files inside.
- The gateway's HTTP platforms (`api_server`, webhooks) need `aiohttp`, which
  upstream only ships in opt-in extras; the buildpack installs the pinned
  version (`HERMES_EXTRA_PACKAGES` in `conf/versions.sh`).

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
