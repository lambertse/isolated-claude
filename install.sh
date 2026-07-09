# 1. Put the files somewhere stable
mkdir -p ~/.local/share/ai-agent-vm
cp Dockerfile entrypoint.sh ai-agent-vm ~/.local/share/ai-agent-vm/
chmod +x ~/.local/share/ai-agent-vm/ai-agent-vm ~/.local/share/ai-agent-vm/entrypoint.sh

# 2. Symlink the launcher onto your PATH
ln -sf ~/.local/share/ai-agent-vm/ai-agent-vm ~/.local/bin/ai-agent-vm
# (make sure ~/.local/bin is in your PATH)

# 3. Build the image (first run will do this automatically, but you can pre-build)
cd ~/.local/share/ai-agent-vm && docker build -t ai-agent-vm:latest .

# 4. Log in once
ai-agent-vm login
