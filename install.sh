# 1. Put the files somewhere stable
mkdir -p ~/.local/share/claude-vm
cp Dockerfile entrypoint.sh claude-vm ~/.local/share/claude-vm/
chmod +x ~/.local/share/claude-vm/claude-vm ~/.local/share/claude-vm/entrypoint.sh

# 2. Symlink the launcher onto your PATH
ln -sf ~/.local/share/claude-vm/claude-vm ~/.local/bin/claude-vm
# (make sure ~/.local/bin is in your PATH)

# 3. Build the image (first run will do this automatically, but you can pre-build)
cd ~/.local/share/claude-vm && docker build -t claude-vm:latest .

# 4. Log in once
claude-vm login
