HERMES_AGENT_VERSION="v0.23.4"
HERMES_AGENT_REPO="https://github.com/NousResearch/hermes-agent.git"
PYTHON_VERSION="3.14"
UV_VERSION="0.13.10"
# Downloaded and extracted into .apt (see lib/apt.sh); python3.14 comes from the
# scalingo-26 base image, git/curl are already in the stack image.
APT_PACKAGES="ripgrep ffmpeg nodejs"
