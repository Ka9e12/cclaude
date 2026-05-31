#!/usr/bin/env bash
set -euo pipefail

PROVIDERS_DIR="$HOME/.claude-providers"

# --- Detect Python command ---
detect_python() {
  for cmd in py python python3; do
    if command -v "$cmd" &>/dev/null && "$cmd" -c "import sqlite3" &>/dev/null; then
      echo "$cmd"
      return 0
    fi
  done
  return 1
}

PYTHON_CMD=$(detect_python) || {
  echo "Error: Python with sqlite3 not found. Install Python and retry." >&2
  exit 1
}

# Convert bash $HOME to Windows path for Python
WIN_HOME=$(cygpath -w "$HOME")
DB_PATH="$HOME/.cc-switch/cc-switch.db"
SETTINGS_PATH="$HOME/.claude/settings.json"
WIN_DB_PATH="$WIN_HOME\\.cc-switch\\cc-switch.db"
WIN_SETTINGS_PATH="$WIN_HOME\\.claude\\settings.json"

die() { echo "Error: $*" >&2; exit 1; }

# --- Validate prerequisites ---
[[ -f "$DB_PATH" ]] || die "cc-switch database not found at $DB_PATH"
[[ -f "$SETTINGS_PATH" ]] || die "Claude settings not found at $SETTINGS_PATH"

# --- Help ---
show_help() {
cat <<'EOF'
Usage:
  cclaude               Interactive provider selection, then launch claude
  cclaude <name>        Launch claude with matched provider (fuzzy match)
  cclaude -l, --list    List all providers without launching
  cclaude -s, --sync    Re-sync all provider config directories from cc-switch
  cclaude -h, --help    Show this help

Each provider runs in its own isolated config directory (~/.claude-providers/<name>/).
Multiple terminals can use different providers simultaneously without conflict.
EOF
}

# --- Read providers from SQLite, output as JSON array to temp file ---
read_providers() {
  local tmp=$(mktemp)
  "$PYTHON_CMD" -c "
import sqlite3, json, re, sys

db = sqlite3.connect(sys.argv[1])
rows = db.execute(
  \"SELECT id, name, settings_config, is_current FROM providers WHERE app_type='claude'\"
).fetchall()
db.close()

providers = []
for r in rows:
    config = json.loads(r[2])
    name = r[1]
    # Generate slug; fall back to provider id if name has no ASCII chars
    slug = re.sub(r'[^a-z0-9]', '-', name.lower()).strip('-')
    slug = re.sub(r'-+', '-', slug)
    if not slug:
        slug = r[0]  # use provider id as fallback
    providers.append({
        'id': r[0],
        'name': name,
        'slug': slug,
        'env': config.get('env', {}),
        'is_current': bool(r[3])
    })
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    json.dump(providers, f, ensure_ascii=False)
" "$WIN_DB_PATH" "$tmp"
  echo "$tmp"
}

# --- List providers ---
list_providers() {
  local providers_file="$1"
  "$PYTHON_CMD" -c "
import json, sys

with open(sys.argv[1], 'r', encoding='utf-8') as f:
    providers = json.load(f)

if not providers:
    print('No Claude providers found in cc-switch database.')
    sys.exit(0)

print('Available providers:')
for i, p in enumerate(providers, 1):
    mark = ' (current)' if p['is_current'] else ''
    print(f'  {i}. {p[\"name\"]}{mark}')
" "$providers_file"
}

# --- Sync a single provider's config directory ---
sync_provider() {
  local slug="$1"
  local env_json_file="$2"
  local provider_dir="$PROVIDERS_DIR/$slug"

  mkdir -p "$provider_dir"

  "$PYTHON_CMD" -c "
import json, sys

# argv[1] = env_json_file (provider env), argv[2] = WIN_SETTINGS_PATH (base settings), argv[3] = output path
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    env_config = json.load(f)

with open(sys.argv[2], 'r', encoding='utf-8') as f:
    settings = json.load(f)

env_config['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] = '1'
settings['env'] = env_config

with open(sys.argv[3], 'w', encoding='utf-8') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write('\n')
" "$env_json_file" "$WIN_SETTINGS_PATH" "$(cygpath -w "$provider_dir/settings.json")"
}

# --- Sync all providers ---
sync_all() {
  local providers_file="$1"
  local count=0

  PROVIDERS_JSON=$(cat "$providers_file")
  TOTAL=$(echo "$PROVIDERS_JSON" | "$PYTHON_CMD" -c "import json,sys; print(len(json.load(sys.stdin)))")

  for i in $(seq 1 "$TOTAL"); do
    NAME=$(echo "$PROVIDERS_JSON" | "$PYTHON_CMD" -c "import json,sys; print(json.load(sys.stdin)[$i-1]['name'])")
    SLUG=$(echo "$PROVIDERS_JSON" | "$PYTHON_CMD" -c "import json,sys; print(json.load(sys.stdin)[$i-1]['slug'])")

    ENV_FILE=$(mktemp)
    echo "$PROVIDERS_JSON" | "$PYTHON_CMD" -c "
import json,sys
data = json.load(sys.stdin)[$i-1]['env']
with open(sys.argv[1], 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False)
" "$ENV_FILE"

    sync_provider "$SLUG" "$ENV_FILE"
    rm -f "$ENV_FILE"
    count=$((count + 1))
    echo "  Synced: $NAME -> ~/.claude-providers/$SLUG/"
  done

  echo "Done. $count providers synced."
}

# --- Main ---
PROVIDERS_FILE=$(read_providers)
trap "rm -f '$PROVIDERS_FILE'" EXIT

# Handle flags
case "${1:-}" in
  -h|--help) show_help; exit 0 ;;
  -l|--list) list_providers "$PROVIDERS_FILE"; exit 0 ;;
  -s|--sync) sync_all "$PROVIDERS_FILE"; exit 0 ;;
esac

# --- Match provider ---
MATCH_FILE=$(mktemp)
trap "rm -f '$PROVIDERS_FILE' '$MATCH_FILE'" EXIT

if [[ -n "${1:-}" ]]; then
  # Fuzzy match by name
  QUERY="$1"
  "$PYTHON_CMD" -c "
import json, sys

with open(sys.argv[1], 'r', encoding='utf-8') as f:
    providers = json.load(f)

query = sys.argv[2].lower()
matches = [p for p in providers if query in p['name'].lower()]

if len(matches) == 1:
    with open(sys.argv[3], 'w', encoding='utf-8') as f:
        json.dump(matches[0], f, ensure_ascii=False)
elif len(matches) > 1:
    names = ', '.join(m['name'] for m in matches)
    print(f'Ambiguous match: {names}', file=sys.stderr)
    sys.exit(1)
else:
    print(f'No provider matching \"{query}\". Use cclaude --list to see available providers.', file=sys.stderr)
    sys.exit(1)
" "$PROVIDERS_FILE" "$QUERY" "$MATCH_FILE"
else
  # Interactive selection
  list_providers "$PROVIDERS_FILE"

  DEFAULT_IDX=$("$PYTHON_CMD" -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    providers = json.load(f)
for i, p in enumerate(providers, 1):
    if p['is_current']:
        print(i)
        break
else:
    print(1)
" "$PROVIDERS_FILE")

  read -rp "Enter number [$DEFAULT_IDX]: " choice
  choice="${choice%$'\r'}"
  [[ -z "$choice" ]] && choice="$DEFAULT_IDX"

  "$PYTHON_CMD" -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    providers = json.load(f)
try:
    idx = int(sys.argv[2])
    if idx < 1 or idx > len(providers):
        print(f'Invalid number. Choose 1-{len(providers)}.', file=sys.stderr)
        sys.exit(1)
    with open(sys.argv[3], 'w', encoding='utf-8') as f:
        json.dump(providers[idx - 1], f, ensure_ascii=False)
except ValueError:
    print('Please enter a number.', file=sys.stderr)
    sys.exit(1)
" "$PROVIDERS_FILE" "$choice" "$MATCH_FILE"
fi

# --- Extract provider info and sync ---
PROVIDER_NAME=$("$PYTHON_CMD" -c "import json,sys; print(json.load(open(sys.argv[1],encoding='utf-8'))['name'])" "$MATCH_FILE")
PROVIDER_SLUG=$("$PYTHON_CMD" -c "import json,sys; print(json.load(open(sys.argv[1],encoding='utf-8'))['slug'])" "$MATCH_FILE")
PROVIDER_DIR="$PROVIDERS_DIR/$PROVIDER_SLUG"

# Extract env to temp file
ENV_FILE=$(mktemp)
trap "rm -f '$PROVIDERS_FILE' '$MATCH_FILE' '$ENV_FILE'" EXIT

"$PYTHON_CMD" -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    json.dump(data['env'], f, ensure_ascii=False)
" "$MATCH_FILE" "$ENV_FILE"

# Sync provider config directory
sync_provider "$PROVIDER_SLUG" "$ENV_FILE"

echo "Using: $PROVIDER_NAME (config: ~/.claude-providers/$PROVIDER_SLUG/)"
echo "Launching claude..."

# Clean up temp files (containing API keys) BEFORE exec replaces this process
rm -f "$PROVIDERS_FILE" "$MATCH_FILE" "$ENV_FILE"

CLAUDE_CONFIG_DIR=$(cygpath -w "$PROVIDER_DIR") exec claude
