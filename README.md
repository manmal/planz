# planz

[![CI](https://github.com/manmal/planz/actions/workflows/ci.yml/badge.svg)](https://github.com/manmal/planz/actions/workflows/ci.yml)
[![Zig](https://img.shields.io/badge/Zig-0.15.2-orange)](https://ziglang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A fast, hierarchical project planning CLI tool written in Zig. Manage tree-structured plans with stable node IDs, cascading status updates, and multiple output formats.

## Features

- **Hierarchical plans** - Up to 4 levels of nesting (phases → tasks → subtasks → details)
- **Stable node IDs** - Reference nodes by ID (`#5`) or path (`"Phase 1/Task A"`)
- **Cascading status** - `done` cascades down to children, `undone` propagates up to ancestors
- **Multiple formats** - Text, JSON, XML, Markdown output
- **SQLite backend** - WAL mode for concurrent access, file-based locking
- **Project-scoped** - Plans are scoped to project directories
- **Single binary** - No dependencies, ~200KB

## Installation

### For AI Coding Agents

Let the agent install it:

**Claude Code** or [**pi**](https://github.com/mariozechner/pi):
```
Read https://code.claude.com/docs/en/skills.md, and then https://raw.githubusercontent.com/manmal/planz/refs/heads/main/README.md, and then install this plan skill.
```

**Codex CLI**:
```
Read https://developers.openai.com/codex/skills.md, and then https://raw.githubusercontent.com/manmal/planz/refs/heads/main/README.md, and then install this plan skill.
```

### From Source

Requires [Zig 0.15+](https://ziglang.org/download/) and SQLite3 development libraries.

**Check prerequisites:**
```bash
# Check Zig
zig version  # should show 0.15.x or higher

# Check SQLite
sqlite3 --version  # should show 3.x.x
pkg-config --modversion sqlite3  # should show version (optional)
```

**Install dependencies:**
```bash
# macOS
brew install zig sqlite3

# Ubuntu/Debian
sudo apt install zig libsqlite3-dev

# Arch Linux
sudo pacman -S zig sqlite
```

**Build and install:**
```bash
git clone https://github.com/manmal/planz.git
cd planz
make all  # builds and installs to ~/.local/bin/planz
```

### Pre-built Binaries

Download from [Releases](https://github.com/manmal/planz/releases) for:
- Linux (x86_64, aarch64) - dynamically links glibc and libsqlite3
- macOS (x86_64, aarch64) - dynamically links system SQLite (included in macOS)
- Windows (x86_64) - dynamically links SQLite3

**Note:** Linux and Windows binaries require SQLite3 to be installed:
```bash
# Ubuntu/Debian
sudo apt install libsqlite3-0

# Windows (via Chocolatey)
choco install sqlite
```

## Quick Start

```bash
# Create a plan
planz create myproject

# Add phases and tasks
planz add myproject "Phase 1: Setup"
planz add myproject "Phase 1: Setup/Install dependencies"
planz add myproject "Phase 1: Setup/Configure environment"
planz add myproject "Phase 2: Implementation"
planz add myproject "Phase 2: Implementation/Build API"

# View the plan
planz show myproject
# Output:
# - [ ] Phase 1: Setup [1]
#   - [ ] Install dependencies [2]
#   - [ ] Configure environment [3]
# - [ ] Phase 2: Implementation [4]
#   - [ ] Build API [5]

# Mark tasks done (by ID or path)
planz done myproject "#2" "#3"

# Check progress
planz progress myproject
# Phase 1: Setup        [####################] 100% (2/2)
# Phase 2: Implementation [--------------------] 0% (0/1)
# Total: 67% (2/3)

# Refine a task into subtasks
planz refine myproject "#5" \
  --add "Design endpoints" \
  --add "Implement handlers" \
  --add "Write tests"

# Export as XML (great for AI agents)
planz show myproject --xml
```

## Commands

### Plan Management

| Command | Description |
|---------|-------------|
| `planz create <plan>` | Create empty plan |
| `planz delete <plan>` | Delete plan and all nodes |
| `planz rename-plan <old> <new>` | Rename a plan |
| `planz list` | List all plans for current project |
| `planz projects` | List all projects with plans |
| `planz summarize <plan> --summary "..."` | Set plan summary |

### Node Management

| Command | Description |
|---------|-------------|
| `planz add <plan> <path> [--desc "..."]` | Add node at path |
| `planz remove <plan> <node> [--force]` | Remove node |
| `planz rename <plan> <node> <new-name>` | Rename node |
| `planz describe <plan> <node> --desc "..."` | Set description |
| `planz move <plan> <node> --to <parent>` | Move to new parent |
| `planz refine <plan> <node> --add <child>...` | Expand leaf into subtree |

### Status

| Command | Description |
|---------|-------------|
| `planz done <plan> <node>...` | Mark done (cascades to children) |
| `planz undone <plan> <node>...` | Mark undone (propagates to ancestors) |

### Viewing

| Command | Description |
|---------|-------------|
| `planz show <plan> [--json\|--xml\|--md]` | Show plan tree |
| `planz progress <plan>` | Show progress per phase |

## Node Identification

Nodes can be referenced two ways:

```bash
# By path (human-readable)
planz done myproject "Phase 1/Setup/Install deps"

# By ID (stable across renames)
planz done myproject "#5"
```

IDs are displayed in output: `- [ ] Install deps [5]`

## Output Formats

### Text (default)
```
- [x] Phase 1: Setup [1]
  - [x] Install deps [2]
- [ ] Phase 2: Build [3]
```

### JSON (`--json`)
```json
[{"id":1,"title":"Phase 1: Setup","done":true,"children":[...]}]
```

### XML (`--xml`)
```xml
<plan name="myproject">
  <node id="1" title="Phase 1: Setup" done="true">
    <node id="2" title="Install deps" done="true" />
  </node>
</plan>
```

### Markdown (`--md`)
```markdown
- [x] Phase 1: Setup [1]
  - [x] Install deps [2]
```

## Options

| Option | Description |
|--------|-------------|
| `--project <path>` | Project directory (default: cwd) |
| `--desc <text>` | Node description |
| `--force` | Force remove nodes with children |
| `--to <parent>` | Target parent for move |
| `--after <sibling>` | Position after sibling |
| `--add <child>` | Child path for refine (repeatable) |

## Data Storage

Plans are stored in `~/.claude/skills/plan/data/plans.db` (SQLite with WAL mode).

## Development

```bash
# Format code
make fmt

# Run linter (max 300 lines per file)
make lint

# Run tests
make test

# Build and install
make all
```

## License

[MIT](LICENSE)
