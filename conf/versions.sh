HERMES_AGENT_VERSION="v0.23.4"
HERMES_AGENT_REPO="https://github.com/NousResearch/hermes-agent.git"
PYTHON_VERSION="3.14"
UV_VERSION="0.13.10"
# Downloaded and extracted into .apt (see lib/apt.sh); python3.14 comes from the
# scalingo-26 base image, git/curl are already in the stack image.
# libopus0 is the Discord voice codec (discord.py[voice] loads libopus.so.0 via
# LD_LIBRARY_PATH, which .profile.d/000_apt.sh points at .apt). libpulse0 ships
# libpulsecommon-*.so, which the apt ffmpeg binary needs at load time (apt
# Recommends are not downloaded in our download-only .apt flow).
APT_PACKAGES="ripgrep ffmpeg nodejs libopus0 libpulse0"
# The gateway's HTTP platforms (api_server, webhooks) need aiohttp, which upstream
# only ships in opt-in extras (messaging/slack/matrix) — pin the same version.
HERMES_EXTRA_PACKAGES="aiohttp==3.14.5"
# Optional uv extras installed from the pinned tag's uv.lock, selected at compile
# time via the app env var HERMES_UV_EXTRAS (e.g. "messaging edge-tts" for
# Telegram/Discord bots + voice, "voice" for local faster-whisper STT).
# Read from ENV_DIR in lib/python.sh (bp_env).
