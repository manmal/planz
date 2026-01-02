---
name: planz
description: Manage hierarchical project plans in SQLite. Tree-based structure with phases and tasks. Multiple output formats (text, JSON, XML, markdown).
---

# planz - Hierarchical Project Planning

Binary: `~/.local/bin/planz` | DB: `~/.claude/skills/plan/data/plans.db` (SQLite WAL)

## Philosophy: Plan in Detail

**Before implementing, create a detailed plan.** Break down work into phases and tasks at the level of detail that makes sense for your current understanding:

- **Early planning**: High-level phases with rough tasks
- **Before implementation**: Detailed tasks you can check off as you go
- **During work**: Add sub-tasks as complexity reveals itself

A good plan:
- Has **3-7 top-level phases** (too few = not broken down enough, too many = overwhelming)
- Uses **action verbs** in task names ("Implement X", "Add Y", "Fix Z")
- Includes **descriptions** for complex items explaining the approach
- Gets **more detailed** as you learn more about the problem

**Update the planz as you work** - mark items done, add new tasks discovered during implementation, refine descriptions. The planz is a living document.

## Overview

Plans are **hierarchical trees** with up to 4 levels of nesting. Each node has:
- **ID** (stable, per-plan auto-increment, shown as `[1]`, `[2]`, etc.)
- **Title** (unique among siblings, no slashes)
- **Description** (optional prose)
- **Done status** (checkbox)

## Node Identification

Nodes can be referenced by **path** OR **ID**:

```bash
# By path (human-readable)
planz done myplan "Phase 1/Database/Create schema"

# By ID (stable, survives renames)
planz done myplan "#5"
```

IDs are shown in output: `- [ ] Create schema [5]`

## Commands

### Plan Management

```bash
planz create <plan>                              # Create empty plan
planz rename-plan <old> <new>                    # Rename a planz  
planz delete <plan>                              # Delete planz and all nodes
planz list                                       # List all plans for project
planz projects                                   # List all projects
planz delete-project                             # Delete project and all plans
planz summarize <plan> --summary "..."           # Set planz summary
```

### Node Management

```bash
planz add <plan> <path> [--desc "..."]           # Add node at path
planz remove <plan> <node> [--force]             # Remove node (--force for children)
planz rename <plan> <node> <new-name>            # Rename node
planz describe <plan> <node> --desc "..."        # Set node description
planz move <plan> <node> --to <parent>           # Move to new parent
planz move <plan> <node> --after <sibling>       # Reorder among siblings
planz refine <plan> <node> --add <child>...      # Expand leaf into subtree
```

### Status

```bash
planz done <plan> <node>...                      # Mark done (cascades DOWN to children)
planz undone <plan> <node>...                    # Mark undone (propagates UP to ancestors)
```

### Viewing

```bash
planz show <plan> [node]                         # Text output (default)
planz show <plan> --json                         # JSON output
planz show <plan> --xml                          # XML output (best for agents)
planz show <plan> --md                           # Markdown output
planz progress <plan>                            # Progress bars per top-level node
```

## Path Syntax

Slash-separated node titles:
```
"Phase 1"                           # Root node
"Phase 1/Database"                  # Child of Phase 1
"Phase 1/Database/Create schema"    # Grandchild
```

- **Max depth**: 4 levels
- **No slashes** allowed in titles
- **Unique titles** within same parent

## Refine Command

Expand a leaf node into a subtree without changing its ID:

```bash
# Before: "Review docs [5]" is a leaf
planz refine myplan "#5" \
  --add "Check API reference" \
  --add "Check API reference/Method signatures" \
  --add "Check API reference/Return types" \
  --add "Update examples"

# After: "Review docs [5]" is now a parent with children [6], [7], [8], [9]
```

## Output Formats

### Text (default)
```
# myplan

- [x] Phase 1: Setup [1]
  - [x] Install deps [2]
  - [x] Configure env [3]
- [ ] Phase 2: Implementation [4]
  - [ ] Build API [5]
```

### XML (`--xml`) - Best for agents
```xml
<?xml version="1.0" encoding="UTF-8"?>
<plan name="myplan">
  <node id="1" title="Phase 1: Setup" done="true">
    <node id="2" title="Install deps" done="true" />
    <node id="3" title="Configure env" done="true" />
  </node>
  <node id="4" title="Phase 2: Implementation" done="false">
    <description>Core implementation work</description>
    <node id="5" title="Build API" done="false" />
  </node>
</plan>
```

### JSON (`--json`)
```json
[{"id":1,"title":"Phase 1: Setup","done":true,"children":[...]}]
```

### Markdown (`--md`)
```markdown
# myplan

- [x] Phase 1: Setup [1]
  - [x] Install deps [2]
```

## Workflow Example

```bash
# 1. Create planz and structure it
planz create auth-system
planz add auth-system "Phase 1: Setup"
planz add auth-system "Phase 1: Setup/Install dependencies"
planz add auth-system "Phase 1: Setup/Configure environment"
planz add auth-system "Phase 2: Implementation"
planz add auth-system "Phase 2: Implementation/OAuth flow"

# 2. Check progress as you work
planz progress auth-system

# 3. Mark items done (by path or ID)
planz done auth-system "#2" "#3"

# 4. Refine a task as you learn more
planz refine auth-system "#5" \
  --add "Login endpoint" \
  --add "Callback endpoint" \
  --add "Token storage"

# 5. View current state
planz show auth-system --xml
```

## Options

| Option | Description |
|--------|-------------|
| `--project <path>` | Project path (default: cwd) |
| `--desc <text>` | Description for add/describe |
| `--summary <text>` | Summary for summarize |
| `--force` | Force remove nodes with children |
| `--json` | JSON output |
| `--xml` | XML output |
| `--md` | Markdown output |
| `--to <path>` | Target parent for move |
| `--after <sibling>` | Sibling to position after |
| `--add <child>` | Child path for refine (repeatable) |

## Exit Codes

- **0**: Success
- **1**: User error (not found, invalid path, etc.)
- **2**: System error (database, lock, etc.)

## Cascade Behavior

- **`done`**: Marks node AND all descendants as done. If all siblings become done, parent auto-marks done.
- **`undone`**: Marks node as undone AND propagates up (all ancestors become undone).
- **`remove`**: Deletes node and all descendants (CASCADE). Use `--force` if node has children.
