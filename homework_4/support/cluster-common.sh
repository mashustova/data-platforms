#!/usr/bin/env bash
set -euo pipefail
EDGE_HOST=team-17-en
SSH_USER=team
HADOOP_USER=hadoop
NN_HOST=team-17-nn
INTERNAL_KEY=${INTERNAL_KEY:-$HOME/.ssh/team_internal}
SSH_OPTIONS=(-i "$INTERNAL_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10)
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
on_node() {
  local host=$1 quoted argument
  shift
  [[ $# -gt 0 ]] || fail 'on_node requires a command'
  quoted=''
  for argument in "$@"; do
    printf -v argument '%q' "$argument"
    quoted+="$argument "
  done
  ssh "${SSH_OPTIONS[@]}" "$SSH_USER@$host" "$quoted"
}
require_edge() {
  [[ $(id -un) == "$SSH_USER" ]] || fail "Run as $SSH_USER on $EDGE_HOST"
  [[ $(hostname -s) == "$EDGE_HOST" ]] || fail "Run on $EDGE_HOST (edge)"
  [[ -r $INTERNAL_KEY ]] || fail "Missing readable internal key: $INTERNAL_KEY"
  for command in ssh scp; do command -v "$command" >/dev/null || fail "Missing $command"; done
}
