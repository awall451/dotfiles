# fzf config — sourced from shell/bashrc

# Use ripgrep for default file/find commands if installed
if command -v rg >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi

export FZF_DEFAULT_OPTS="
  --height=40%
  --layout=reverse
  --border
  --info=inline
  --prompt='> '
  --pointer='▶'
  --marker='✓'
"

# Preview file contents with bat (if available) when using Ctrl-T
if command -v bat >/dev/null 2>&1; then
  export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:200 {}'"
fi

# Load fzf key bindings + completion (Arch installs to /usr/share/fzf/, Debian/Ubuntu to /usr/share/doc/fzf/)
for f in /usr/share/fzf/key-bindings.bash /usr/share/fzf/completion.bash \
         /usr/share/doc/fzf/examples/key-bindings.bash /usr/share/doc/fzf/examples/completion.bash; do
  [ -f "$f" ] && source "$f"
done
