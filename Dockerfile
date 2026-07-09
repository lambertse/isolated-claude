# AI Agent VM image — minimal, arm64/amd64, Node LTS + the AI Agent CLI package.
FROM node:22-slim

# Minimal runtime deps. ca-certificates for HTTPS, tini for proper signal handling,
# curl for healthchecks / manual debugging. No git (intentional per user request).
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      tini \
      curl \
    && rm -rf /var/lib/apt/lists/*

# Install the AI Agent CLI globally. Package name is fixed upstream (published to npm)
# and cannot be renamed here.
RUN npm install -g @anthropic-ai/claude-code && npm cache clean --force

# Entrypoint that wires up ~/.claude.json from inside the auth volume.
# The AI Agent CLI stores account state in ~/.claude.json (a file, not the .claude/ dir) —
# a path hardcoded by the CLI itself, not something we choose.
# We keep the real file inside the volume at ~/.claude/_home_agent.json and symlink
# ~/.claude.json -> that path, so it persists across containers just like .credentials.json.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Run as the non-root `node` user that the base image already provides (uid 1000).
# Its HOME is /home/node. The AI Agent CLI stores credentials under ~/.claude.
USER node
WORKDIR /workspace

# The auth volume will be mounted at /home/node/.claude by the launcher.
# We don't VOLUME-declare it here so the launcher controls lifecycle.

ENV TERM=xterm-256color \
    CLAUDE_CODE_DISABLE_TELEMETRY=1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
# Default command keeps container alive so the launcher can `docker exec` into it.
CMD ["sleep", "infinity"]

