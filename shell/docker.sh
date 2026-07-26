#
# Docker helpers. Sourced from shell/bashrc.
#
# Generic distillation of a work VM helper script: same command names (so
# muscle memory carries over) but no project-specific paths, container-name
# prefixes, or env vars. Every filter argument is optional and defaults to
# "all containers".

command -v docker >/dev/null 2>&1 || return 0

# ----- Listing

# dps [name-filter] — formatted `docker ps -a` (name / age / status)
dps() {
  if [ -n "$1" ]; then
    docker ps -a --filter "name=$1" --format="table {{.Names}}\t{{.RunningFor}}\t{{.Status}}"
  else
    docker ps -a --format="table {{.Names}}\t{{.RunningFor}}\t{{.Status}}"
  fi
}

# wdps [name-filter] — dps on a 1s watch
wdps() {
  local filter=""
  [ -n "$1" ] && filter="--filter \"name=$1\""
  watch -n 1 "docker ps -a $filter --format=\"table {{.Names}}\t{{.RunningFor}}\t{{.Status}}\""
}

# docker-stats — formatted `docker stats` for all containers
alias docker-stats='docker stats --all --format "table {{.Container}}\t{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}"'

# docker-mem [regex] — `docker stats` filtered by regex, with a total in GiB
docker-mem() {
  docker stats --no-stream \
  | perl -nale 'BEGIN{ $REGEX = $ARGV[0] // "\\w"; @ARGV=(); }
                ( $.<2 || /$REGEX/ ) && print;
                /$REGEX/ || next;
                ($a,$b) = ($1,$2) if $F[3] =~ /^(\d+(?:\.\d+)?)(\w+)/;
                $b =~ /^[MG]iB/ || next;
                $a = $a * 1024 if ($b eq "GiB");
                $t = $t + $a;
                END{ printf "\nMem usage total" . ($REGEX eq "\\w" ? "" : " for /$REGEX/") . ": %0.3f GiB\n\n", $t / 1024; }' $1
}

# ----- Health

# dih [name-filter] — one line per container: name, health status, last probe output
dih() {
  local search_string="${1:-}"
  docker ps --filter "name=$search_string" --format "{{.Names}}" | while read -r name; do
    health_status=$(docker inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}No health check available{{end}}" "$name")
    if [[ "$health_status" != "No health check available" ]]; then
      latest_output=$(docker inspect --format "{{json .State.Health.Log}}" "$name" | jq -r ".[-1].Output" | tr '\n' ' ')
    else
      latest_output="No health check found"
    fi
    printf "%-40s %-20s %-80s\n" "$name" "$health_status" "$latest_output"
  done
}

# wdih [name-filter] — dih on a 10s watch
wdih() {
  local search_string="${1:-}"
  watch -n 10 "docker ps --filter \"name=$search_string\" --format \"{{.Names}}\" | while read -r name; do \
      health_status=\$(docker inspect --format \"{{if .State.Health}}{{.State.Health.Status}}{{else}}No health check available{{end}}\" \"\$name\"); \
      if [[ \"\$health_status\" != \"No health check available\" ]]; then \
          latest_output=\$(docker inspect --format \"{{json .State.Health.Log}}\" \"\$name\" | jq -r \".[-1].Output\" | tr '\n' ' '); \
      else \
          latest_output=\"No health check found\"; \
      fi; \
      printf \"%-40s %-20s %-80s\n\" \"\$name\" \"\$health_status\" \"\$latest_output\"; \
  done"
}

# dihj <partial-name> — full .State.Health JSON for the first matching container:
# every probe in the log, ExitCode, FailingStreak. For when dih's last-output
# line is not enough (flapping probes, non-zero exits).
dihj() {
  local partial_name=$1 container_id
  if [ -z "$partial_name" ]; then
    echo "Usage: dihj <partial_container_name>"
    return 1
  fi
  container_id=$(docker ps --filter "name=$partial_name" --format "{{.ID}}" | head -n 1)

  if [ -z "$container_id" ]; then
    echo "Container not found for name: $partial_name"
    return 1
  fi

  docker inspect --format "{{json .State.Health }}" "$container_id" | jq
}

# ----- Shells into containers / images

# deit <partial-name> [cmd ...] — exec into the first matching running container (default: sh)
deit() {
  if [ "$#" -lt 1 ]; then
    echo "Usage: deit <partial_container_name> [<command>]"
    return 1
  fi

  local search_string="$1" command container_name
  shift

  if [ "$#" -eq 0 ]; then
    command="sh"
  else
    command="$1"
    shift
  fi

  container_name=$(docker ps --filter "name=$search_string" --format "{{.Names}}" | head -n 1)

  if [ -z "$container_name" ]; then
    echo "No matching containers found."
    return 1
  fi

  docker exec -it "$container_name" "$command" "$@"
}

# drit <image> — throwaway interactive bash in a fresh container from an image
alias drit='docker run --rm -it --entrypoint bash'
# dritu <image> — same, as root, privileged
alias dritu='docker run --privileged --user=root --rm -it --entrypoint bash'

# ----- Image inspection

# dil <image-tag|container-name> — print an image's labels
dil() {
  if [ "$#" -lt 1 ]; then
    echo "Usage: dil <image-tag|container-name>"
    return 1
  fi

  local input=$1 image_tag

  if [[ "$input" == *":"* ]]; then
    image_tag="$input"
  else
    # Treat it as a container name and resolve the image it runs
    image_tag=$(docker ps -a --filter "name=$input" --format "{{.Image}}" | head -n 1)
  fi

  if [ -z "$image_tag" ]; then
    echo "Error: no image found for '$input'."
    return 1
  fi

  docker inspect "$image_tag" | jq '.[0].Config.Labels'
}

# ctop — htop-style container metrics (runs from a container, nothing to install)
alias ctop='docker run --rm -ti --name=ctop --volume /var/run/docker.sock:/var/run/docker.sock:ro quay.io/vektorlab/ctop:latest'
# dive <image> — explore image layers / Dockerfile history
alias dive='docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock wagoodman/dive:latest'

# ----- Compose (operate on the compose project in the current directory)

alias dc='docker compose'
alias dcp='docker compose pull'
alias dcud='docker compose up -d'
alias dcd='docker compose down'
alias dcps='docker compose ps'
alias dclf='docker compose logs -f --tail=1000'

# dcpsg <service-pattern> <compose-cmd> — run a compose command against every
# service whose name matches the pattern, eg: dcpsg worker restart
dcpsg() {
  if [ "$#" -lt 2 ]; then
    echo "Usage: dcpsg <service_pattern> <compose_command>"
    return 1
  fi
  docker compose ps --services | grep "$1" | xargs docker compose "$2"
}

# ----- Cheat sheet

dockerstuff() {
  local b=$'\033[1m' c=$'\033[36m' g=$'\033[32m' y=$'\033[33m' d=$'\033[2m' r=$'\033[0m'
  cat <<EOF
${c}${b}== Docker helpers ==${r} ${d}(every [filter] is optional; omit for all containers)${r}

${g}${b}listing${r}
  ${y}dps${r} [filter]           ${d}# name / age / status table (includes stopped)${r}
  ${y}wdps${r} [filter]          ${d}# dps on a 1s watch${r}
  ${y}docker-stats${r}           ${d}# formatted docker stats, all containers${r}
  ${y}docker-mem${r} [regex]     ${d}# stats filtered by regex + total GiB${r}

${g}${b}health${r}
  ${y}dih${r} [filter]           ${d}# one line per container: status + last probe output${r}
  ${y}wdih${r} [filter]          ${d}# dih on a 10s watch${r}
  ${y}dihj${r} <partial>         ${d}# full health JSON: all probes, ExitCode, FailingStreak${r}

${g}${b}shells${r}
  ${y}deit${r} <partial> [cmd]   ${d}# exec into first matching container (default sh)${r}
  ${y}drit${r} <image>           ${d}# throwaway interactive bash from an image${r}
  ${y}dritu${r} <image>          ${d}# same, root + privileged${r}

${g}${b}images${r}
  ${y}dil${r} <image|container>  ${d}# print image labels${r}
  ${y}dive${r} <image>           ${d}# layer / Dockerfile explorer (containerized)${r}
  ${y}ctop${r}                   ${d}# htop for containers (containerized)${r}

${g}${b}compose${r} ${d}(cwd's compose project)${r}
  ${y}dc${r} / ${y}dcp${r} / ${y}dcud${r} / ${y}dcd${r} / ${y}dcps${r} / ${y}dclf${r}
  ${d}compose / pull / up -d / down / ps / logs -f --tail=1000${r}
  ${y}dcpsg${r} <pattern> <cmd>  ${d}# run cmd against every matching service, eg: dcpsg worker restart${r}

${d}Run 'dockerstuff' anytime to see this again.${r}
EOF
}
