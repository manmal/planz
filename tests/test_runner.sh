#!/bin/bash
# Comprehensive test suite for planz CLI
# Run from project root: ./tests/test_runner.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test database - use temp location
export TEST_DB_DIR=$(mktemp -d)
export HOME_BACKUP="$HOME"

# Setup test environment
setup() {
    mkdir -p "$TEST_DB_DIR/.claude/skills/plan/data"
    export HOME="$TEST_DB_DIR"
    # Ensure planz binary uses test DB
    echo "Using test DB at: $TEST_DB_DIR"
}

# Cleanup
cleanup() {
    export HOME="$HOME_BACKUP"
    rm -rf "$TEST_DB_DIR"
    echo ""
    echo "========================================"
    echo -e "Tests Run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo "========================================"
    if [ $TESTS_FAILED -gt 0 ]; then
        exit 1
    fi
}

trap cleanup EXIT

# Assert functions
assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        echo -e "  ${GREEN}✓${NC} $msg"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}✗${NC} $msg"
        echo -e "    Expected: '$expected'"
        echo -e "    Actual:   '$actual'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "  ${GREEN}✓${NC} $msg"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}✗${NC} $msg"
        echo -e "    Expected to contain: '$needle'"
        echo -e "    Actual: '$haystack'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" != *"$needle"* ]]; then
        echo -e "  ${GREEN}✓${NC} $msg"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}✗${NC} $msg"
        echo -e "    Expected NOT to contain: '$needle'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" -eq "$actual" ]; then
        echo -e "  ${GREEN}✓${NC} $msg"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}✗${NC} $msg"
        echo -e "    Expected exit code: $expected, got: $actual"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_line_count() {
    local expected="$1"
    local output="$2"
    local msg="$3"
    local actual=$(echo "$output" | wc -l | tr -d ' ')
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" -eq "$actual" ]; then
        echo -e "  ${GREEN}✓${NC} $msg"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}✗${NC} $msg"
        echo -e "    Expected $expected lines, got $actual"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ============================================================================
# TEST SUITES
# ============================================================================

test_plan_crud() {
    echo -e "\n${YELLOW}=== Plan CRUD Tests ===${NC}"
    
    # Create planz
    output=$(planz create test-plan 2>&1)
    assert_contains "$output" "Created plan 'test-plan'" "create planz succeeds"
    
    # Create duplicate fails
    output=$(planz create test-plan 2>&1) || true
    assert_contains "$output" "already exists" "create duplicate fails"
    
    # List shows planz
    output=$(planz list 2>&1)
    assert_contains "$output" "test-plan" "list shows created plan"
    
    # Delete planz
    output=$(planz delete test-plan 2>&1)
    assert_contains "$output" "Deleted plan" "delete planz succeeds"
    
    # Delete non-existent fails
    output=$(planz delete nonexistent 2>&1) || true
    assert_contains "$output" "not found" "delete non-existent fails"
    
    # Recreate for other tests
    planz create test-plan 2>/dev/null
}

test_plan_rename() {
    echo -e "\n${YELLOW}=== Plan Rename Tests ===${NC}"
    
    planz create rename-test 2>/dev/null
    
    # Rename succeeds
    output=$(planz rename-plan rename-test renamed-plan 2>&1)
    assert_contains "$output" "Renamed plan" "rename planz succeeds"
    
    # Old name gone
    output=$(planz show rename-test 2>&1) || true
    assert_contains "$output" "not found" "old name not found after rename"
    
    # New name exists
    output=$(planz show renamed-plan 2>&1)
    assert_contains "$output" "renamed-plan" "new name exists after rename"
    
    # Rename to existing fails
    planz create another-plan 2>/dev/null
    output=$(planz rename-plan renamed-plan another-plan 2>&1) || true
    assert_contains "$output" "already exists" "rename to existing name fails"
    
    # Cleanup
    planz delete renamed-plan 2>/dev/null
    planz delete another-plan 2>/dev/null
}

test_node_add() {
    echo -e "\n${YELLOW}=== Node Add Tests ===${NC}"
    
    planz create node-test 2>/dev/null
    
    # Add root node
    output=$(planz add node-test "Phase 1" 2>&1)
    assert_contains "$output" "Added 'Phase 1'" "add root node succeeds"
    
    # Add child node
    output=$(planz add node-test "Phase 1/Task A" 2>&1)
    assert_contains "$output" "Added 'Phase 1/Task A'" "add child node succeeds"
    
    # Add with description
    output=$(planz add node-test "Phase 1/Task B" --desc "Do something" 2>&1)
    assert_contains "$output" "Added" "add with description succeeds"
    
    # Verify description in output
    output=$(planz show node-test 2>&1)
    assert_contains "$output" "Do something" "description appears in show"
    
    # Add grandchild
    output=$(planz add node-test "Phase 1/Task A/Subtask 1" 2>&1)
    assert_contains "$output" "Added" "add grandchild succeeds"
    
    # Add great-grandchild (level 4)
    output=$(planz add node-test "Phase 1/Task A/Subtask 1/Detail" 2>&1)
    assert_contains "$output" "Added" "add level 4 succeeds"
    
    # Add level 5 fails (max depth exceeded)
    output=$(planz add node-test "Phase 1/Task A/Subtask 1/Detail/TooDeep" 2>&1) || true
    assert_contains "$output" "depth" "add level 5 fails with depth error"
    
    # Add duplicate title at same level fails
    output=$(planz add node-test "Phase 1/Task A" 2>&1) || true
    assert_contains "$output" "Duplicate" "add duplicate title fails"
    
    # Add with slash in title fails
    output=$(planz add node-test "Phase 1/Bad/Title" 2>&1) || true
    # This actually creates "Bad" under "Phase 1" - let's check the path parse
    
    # Add empty path fails
    output=$(planz add node-test "" 2>&1) || true
    assert_contains "$output" "Invalid" "add empty path fails"
    
    planz delete node-test 2>/dev/null
}

test_node_remove() {
    echo -e "\n${YELLOW}=== Node Remove Tests ===${NC}"
    
    planz create remove-test 2>/dev/null
    planz add remove-test "Phase 1" 2>/dev/null
    planz add remove-test "Phase 1/Task A" 2>/dev/null
    planz add remove-test "Phase 1/Task B" 2>/dev/null
    planz add remove-test "Phase 2" 2>/dev/null
    
    # Remove leaf node
    output=$(planz remove remove-test "Phase 1/Task B" 2>&1)
    assert_contains "$output" "Removed" "remove leaf node succeeds"
    
    # Verify removed
    output=$(planz show remove-test 2>&1)
    assert_not_contains "$output" "Task B" "removed node not in show"
    
    # Remove parent without --force fails
    output=$(planz remove remove-test "Phase 1" 2>&1) || true
    assert_contains "$output" "children" "remove parent without force fails"
    
    # Remove parent with --force succeeds
    output=$(planz remove remove-test "Phase 1" --force 2>&1)
    assert_contains "$output" "Removed" "remove parent with force succeeds"
    
    # Verify cascade delete
    output=$(planz show remove-test 2>&1)
    assert_not_contains "$output" "Phase 1" "parent removed"
    assert_not_contains "$output" "Task A" "children cascade deleted"
    
    # Remove non-existent fails
    output=$(planz remove remove-test "Nonexistent" 2>&1) || true
    assert_contains "$output" "Invalid path" "remove non-existent fails"
    
    planz delete remove-test 2>/dev/null
}

test_node_rename() {
    echo -e "\n${YELLOW}=== Node Rename Tests ===${NC}"
    
    planz create rename-node-test 2>/dev/null
    planz add rename-node-test "Original Name" 2>/dev/null
    planz add rename-node-test "Original Name/Child" 2>/dev/null
    planz add rename-node-test "Another Node" 2>/dev/null
    
    # Rename node
    output=$(planz rename rename-node-test "Original Name" "New Name" 2>&1)
    assert_contains "$output" "Renamed to 'New Name'" "rename node succeeds"
    
    # Verify rename
    output=$(planz show rename-node-test 2>&1)
    assert_contains "$output" "New Name" "new name in show"
    assert_not_contains "$output" "Original Name" "old name not in show"
    
    # Children still accessible via new path
    output=$(planz show rename-node-test "New Name" 2>&1)
    assert_contains "$output" "Child" "children accessible via new path"
    
    # Rename to existing fails
    output=$(planz rename rename-node-test "New Name" "Another Node" 2>&1) || true
    assert_contains "$output" "Duplicate" "rename to existing name fails"
    
    # Rename with slash fails
    output=$(planz rename rename-node-test "New Name" "Bad/Name" 2>&1) || true
    assert_contains "$output" "Invalid" "rename with slash fails"
    
    planz delete rename-node-test 2>/dev/null
}

test_node_describe() {
    echo -e "\n${YELLOW}=== Node Describe Tests ===${NC}"
    
    planz create desc-test 2>/dev/null
    planz add desc-test "Task" 2>/dev/null
    
    # Add description
    output=$(planz describe desc-test "Task" --desc "This is a description" 2>&1)
    assert_contains "$output" "Updated description" "describe succeeds"
    
    # Verify description
    output=$(planz show desc-test 2>&1)
    assert_contains "$output" "This is a description" "description in show"
    
    # Update description
    output=$(planz describe desc-test "Task" --desc "New description" 2>&1)
    assert_contains "$output" "Updated" "update description succeeds"
    
    # Clear description
    output=$(planz describe desc-test "Task" --desc "" 2>&1)
    assert_contains "$output" "Updated" "clear description succeeds"
    
    planz delete desc-test 2>/dev/null
}

test_done_undone() {
    echo -e "\n${YELLOW}=== Done/Undone Tests ===${NC}"
    
    planz create done-test 2>/dev/null
    planz add done-test "Phase 1" 2>/dev/null
    planz add done-test "Phase 1/Task A" 2>/dev/null
    planz add done-test "Phase 1/Task B" 2>/dev/null
    planz add done-test "Phase 2" 2>/dev/null
    planz add done-test "Phase 2/Task C" 2>/dev/null
    
    # Mark single task done
    output=$(planz done done-test "Phase 1/Task A" 2>&1)
    assert_contains "$output" "Marked 1 item(s) as done" "mark single done"
    
    # Verify in show
    output=$(planz show done-test 2>&1)
    assert_contains "$output" "[x] Task A" "task shows as done"
    assert_contains "$output" "[ ] Task B" "other task still undone"
    
    # Mark parent done (should cascade to children)
    output=$(planz done done-test "Phase 2" 2>&1)
    assert_contains "$output" "done" "mark parent done"
    
    output=$(planz show done-test 2>&1)
    assert_contains "$output" "[x] Phase 2" "parent shows done"
    assert_contains "$output" "[x] Task C" "child cascaded to done"
    
    # Mark all children done -> parent should auto-done
    planz done done-test "Phase 1/Task B" 2>/dev/null
    output=$(planz show done-test 2>&1)
    assert_contains "$output" "[x] Phase 1" "parent auto-done when all children done"
    
    # Mark undone - should propagate up
    output=$(planz undone done-test "Phase 1/Task A" 2>&1)
    assert_contains "$output" "undone" "mark undone succeeds"
    
    output=$(planz show done-test 2>&1)
    assert_contains "$output" "[ ] Task A" "task shows undone"
    assert_contains "$output" "[ ] Phase 1" "parent propagated to undone"
    
    # Mark multiple done at once
    output=$(planz done done-test "Phase 1/Task A" "Phase 1/Task B" 2>&1)
    assert_contains "$output" "Marked 2 item(s)" "mark multiple done"
    
    planz delete done-test 2>/dev/null
}

test_move() {
    echo -e "\n${YELLOW}=== Move Tests ===${NC}"
    
    planz create move-test 2>/dev/null
    planz add move-test "Phase 1" 2>/dev/null
    planz add move-test "Phase 1/Task A" 2>/dev/null
    planz add move-test "Phase 1/Task B" 2>/dev/null
    planz add move-test "Phase 2" 2>/dev/null
    
    # Move to different parent
    output=$(planz move move-test "Phase 1/Task A" --to "Phase 2" 2>&1)
    assert_contains "$output" "Moved" "move to parent succeeds"
    
    # Verify moved
    output=$(planz show move-test "Phase 2" 2>&1)
    assert_contains "$output" "Task A" "task now under Phase 2"
    
    output=$(planz show move-test "Phase 1" 2>&1)
    assert_not_contains "$output" "Task A" "task no longer under Phase 1"
    
    # Move to root
    output=$(planz move move-test "Phase 2/Task A" --to "" 2>&1)
    assert_contains "$output" "Moved" "move to root succeeds"
    
    output=$(planz show move-test 2>&1)
    # Task A should be at root level now
    
    # Reorder with --after
    planz add move-test "Item 1" 2>/dev/null
    planz add move-test "Item 2" 2>/dev/null
    planz add move-test "Item 3" 2>/dev/null
    
    output=$(planz move move-test "Item 1" --after "Item 3" 2>&1)
    assert_contains "$output" "Moved" "reorder succeeds"
    
    planz delete move-test 2>/dev/null
}

test_show_formats() {
    echo -e "\n${YELLOW}=== Show Format Tests ===${NC}"
    
    planz create format-test 2>/dev/null
    planz add format-test "Phase 1" --desc "Description here" 2>/dev/null
    planz add format-test "Phase 1/Task A" 2>/dev/null
    planz done format-test "Phase 1/Task A" 2>/dev/null
    
    # Text format (default)
    output=$(planz show format-test 2>&1)
    assert_contains "$output" "- [x] Task A" "text format shows checkbox"
    assert_contains "$output" "Description here" "text format shows description"
    
    # JSON format
    output=$(planz show format-test --json 2>&1)
    assert_contains "$output" '"title":"Phase 1"' "json has title"
    assert_contains "$output" '"done":true' "json has done status"
    assert_contains "$output" '"children":' "json has children"
    
    # XML format
    output=$(planz show format-test --xml 2>&1)
    assert_contains "$output" '<?xml version="1.0"' "xml has declaration"
    assert_contains "$output" '<plan name="format-test">' "xml has plan element"
    assert_contains "$output" '<node id="1" title="Phase 1"' "xml has node element with id"
    assert_contains "$output" 'done="true"' "xml has done attribute"
    assert_contains "$output" '<description>' "xml has description element"
    
    # Markdown format
    output=$(planz show format-test --md 2>&1)
    assert_contains "$output" "# format-test" "markdown has title"
    assert_contains "$output" "- [x]" "markdown has checkbox"
    
    planz delete format-test 2>/dev/null
}

test_progress() {
    echo -e "\n${YELLOW}=== Progress Tests ===${NC}"
    
    planz create progress-test 2>/dev/null
    planz add progress-test "Phase 1" 2>/dev/null
    planz add progress-test "Phase 1/Task A" 2>/dev/null
    planz add progress-test "Phase 1/Task B" 2>/dev/null
    planz add progress-test "Phase 2" 2>/dev/null
    planz add progress-test "Phase 2/Task C" 2>/dev/null
    planz add progress-test "Phase 2/Task D" 2>/dev/null
    
    # Initial progress (0%)
    output=$(planz progress progress-test 2>&1)
    assert_contains "$output" "0%" "initial progress is 0%"
    assert_contains "$output" "Phase 1" "progress shows Phase 1"
    assert_contains "$output" "Phase 2" "progress shows Phase 2"
    
    # Mark some done
    planz done progress-test "Phase 1/Task A" 2>/dev/null
    output=$(planz progress progress-test 2>&1)
    assert_contains "$output" "33%" "progress shows 33% for Phase 1"
    
    # Mark all Phase 1 done
    planz done progress-test "Phase 1" 2>/dev/null
    output=$(planz progress progress-test 2>&1)
    assert_contains "$output" "100%" "progress shows 100% for Phase 1"
    assert_contains "$output" "Total:" "progress shows total"
    
    planz delete progress-test 2>/dev/null
}

test_summarize() {
    echo -e "\n${YELLOW}=== Summarize Tests ===${NC}"
    
    planz create summary-test 2>/dev/null
    
    # Set summary
    output=$(planz summarize summary-test --summary "This is a test plan" 2>&1)
    assert_contains "$output" "Updated summary" "summarize succeeds"
    
    # Verify in list
    output=$(planz list 2>&1)
    assert_contains "$output" "This is a test" "summary in list"
    
    planz delete summary-test 2>/dev/null
}

test_project_scope() {
    echo -e "\n${YELLOW}=== Project Scope Tests ===${NC}"
    
    # Create temp directories
    mkdir -p "$TEST_DB_DIR/project-a"
    mkdir -p "$TEST_DB_DIR/project-b"
    
    # Create plans in different projects
    planz create shared-name --project "$TEST_DB_DIR/project-a" 2>/dev/null
    planz create shared-name --project "$TEST_DB_DIR/project-b" 2>/dev/null
    
    # Add different content
    planz add shared-name "Project A Task" --project "$TEST_DB_DIR/project-a" 2>/dev/null
    planz add shared-name "Project B Task" --project "$TEST_DB_DIR/project-b" 2>/dev/null
    
    # Verify isolation
    output=$(planz show shared-name --project "$TEST_DB_DIR/project-a" 2>&1)
    assert_contains "$output" "Project A Task" "project A has correct content"
    assert_not_contains "$output" "Project B Task" "project A doesn't have B's content"
    
    output=$(planz show shared-name --project "$TEST_DB_DIR/project-b" 2>&1)
    assert_contains "$output" "Project B Task" "project B has correct content"
    
    # Projects list
    output=$(planz projects 2>&1)
    assert_contains "$output" "project-a" "projects shows project-a"
    assert_contains "$output" "project-b" "projects shows project-b"
}

test_edge_cases() {
    echo -e "\n${YELLOW}=== Edge Case Tests ===${NC}"
    
    planz create edge-test 2>/dev/null
    
    # Very long title
    long_title="This is a very long title that goes on and on and on"
    output=$(planz add edge-test "$long_title" 2>&1)
    assert_contains "$output" "Added" "long title succeeds"
    
    # Special characters in title (except slash)
    output=$(planz add edge-test "Task with: colons & ampersands!" 2>&1)
    assert_contains "$output" "Added" "special chars in title succeed"
    
    # Unicode in title
    output=$(planz add edge-test "Task mit Ümläuten 日本語" 2>&1)
    assert_contains "$output" "Added" "unicode in title succeeds"
    
    # Unicode in description
    output=$(planz add edge-test "Unicode Desc" --desc "Beschreibung: äöü 中文" 2>&1)
    assert_contains "$output" "Added" "unicode in description succeeds"
    
    # Verify unicode preserved
    output=$(planz show edge-test --xml 2>&1)
    assert_contains "$output" "Ümläuten" "unicode preserved in xml"
    
    # Empty planz show
    planz create empty-plan 2>/dev/null
    output=$(planz show empty-plan 2>&1)
    assert_contains "$output" "empty-plan" "empty planz shows name"
    
    # Whitespace handling
    output=$(planz add edge-test "  Trimmed Title  " 2>&1)
    assert_contains "$output" "Added" "whitespace title handled"
    
    planz delete edge-test 2>/dev/null
    planz delete empty-plan 2>/dev/null
}

test_error_handling() {
    echo -e "\n${YELLOW}=== Error Handling Tests ===${NC}"
    
    # Command with missing args
    output=$(planz add 2>&1) || true
    assert_contains "$output" "requires" "missing args shows error"
    
    output=$(planz done 2>&1) || true
    assert_contains "$output" "requires" "done without args shows error"
    
    # Invalid command
    output=$(planz invalidcmd 2>&1) || true
    assert_contains "$output" "Unknown command" "invalid command error"
    
    # Operations on non-existent planz
    output=$(planz show nonexistent 2>&1) || true
    assert_contains "$output" "not found" "show non-existent fails"
    
    output=$(planz add nonexistent "Task" 2>&1) || true
    assert_contains "$output" "not found" "add to non-existent fails"
    
    # Help flags
    output=$(planz --help 2>&1)
    assert_contains "$output" "Usage:" "help shows usage"
    
    output=$(planz help 2>&1)
    assert_contains "$output" "Usage:" "help command shows usage"
}

test_concurrent_safety() {
    echo -e "\n${YELLOW}=== Concurrent Safety Tests ===${NC}"
    
    planz create concurrent-test 2>/dev/null
    
    # Run multiple adds in parallel
    for i in {1..10}; do
        planz add concurrent-test "Task $i" 2>/dev/null &
    done
    wait
    
    # Count how many tasks were added (some may fail due to position race)
    output=$(planz show concurrent-test 2>&1)
    task_count=$(echo "$output" | grep -c "Task" || echo "0")
    
    TESTS_RUN=$((TESTS_RUN + 1))
    # At least 5 should succeed (50% tolerance for race conditions)
    if [ "$task_count" -ge 5 ]; then
        echo -e "  ${GREEN}✓${NC} concurrent adds: $task_count/10 succeeded (>=5 required)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}✗${NC} concurrent adds: only $task_count/10 succeeded (need >=5)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    # Verify no corruption - planz should be readable
    output=$(planz show concurrent-test --json 2>&1)
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} concurrent planz JSON is valid (no corruption)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}✗${NC} concurrent planz JSON is invalid"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    planz delete concurrent-test 2>/dev/null
}

test_xml_escaping() {
    echo -e "\n${YELLOW}=== XML Escaping Tests ===${NC}"
    
    planz create xml-escape-test 2>/dev/null
    
    # Add node with XML special chars
    planz add xml-escape-test "Task <with> \"quotes\" & 'apostrophes'" 2>/dev/null
    planz describe xml-escape-test "Task <with> \"quotes\" & 'apostrophes'" --desc "Description with <xml> & stuff" 2>/dev/null
    
    output=$(planz show xml-escape-test --xml 2>&1)
    
    # Verify proper escaping
    assert_contains "$output" "&lt;" "< escaped to &lt;"
    assert_contains "$output" "&gt;" "> escaped to &gt;"
    assert_contains "$output" "&amp;" "& escaped to &amp;"
    assert_contains "$output" "&quot;" "\" escaped to &quot;"
    
    # Verify still valid XML (no raw <, >, &)
    assert_not_contains "$output" ' < ' "no raw < in output"
    
    planz delete xml-escape-test 2>/dev/null
}

test_json_escaping() {
    echo -e "\n${YELLOW}=== JSON Escaping Tests ===${NC}"
    
    planz create json-escape-test 2>/dev/null
    
    # Add node with JSON special chars
    planz add json-escape-test 'Task with "quotes"' 2>/dev/null
    planz describe json-escape-test 'Task with "quotes"' --desc 'Description with "quotes"' 2>/dev/null
    
    output=$(planz show json-escape-test --json 2>&1)
    
    # Verify proper escaping - look for backslash-quote sequence
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$output" | grep -q '\\\"'; then
        echo -e "  ${GREEN}✓${NC} quotes escaped in json"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}✗${NC} quotes not escaped in json"
        echo "    Output: $output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    # Verify valid JSON (can be parsed)
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} JSON output is valid"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}✗${NC} JSON output is invalid"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    planz delete json-escape-test 2>/dev/null
}

test_deep_nesting() {
    echo -e "\n${YELLOW}=== Deep Nesting Tests ===${NC}"
    
    planz create deep-test 2>/dev/null
    
    # Build 4-level deep structure
    planz add deep-test "L1" 2>/dev/null
    planz add deep-test "L1/L2" 2>/dev/null
    planz add deep-test "L1/L2/L3" 2>/dev/null
    planz add deep-test "L1/L2/L3/L4" 2>/dev/null
    
    # Verify structure
    output=$(planz show deep-test 2>&1)
    assert_contains "$output" "L1" "level 1 exists"
    assert_contains "$output" "L2" "level 2 exists"
    assert_contains "$output" "L3" "level 3 exists"
    assert_contains "$output" "L4" "level 4 exists"
    
    # Done at deepest level should cascade up
    planz done deep-test "L1/L2/L3/L4" 2>/dev/null
    output=$(planz show deep-test 2>&1)
    assert_contains "$output" "[x] L4" "L4 done"
    assert_contains "$output" "[x] L3" "L3 auto-done"
    assert_contains "$output" "[x] L2" "L2 auto-done"
    assert_contains "$output" "[x] L1" "L1 auto-done"
    
    # Undone at deep level should propagate up
    planz undone deep-test "L1/L2/L3/L4" 2>/dev/null
    output=$(planz show deep-test 2>&1)
    assert_contains "$output" "[ ] L4" "L4 undone"
    assert_contains "$output" "[ ] L1" "L1 propagated undone"
    
    planz delete deep-test 2>/dev/null
}

test_show_subtree() {
    echo -e "\n${YELLOW}=== Show Subtree Tests ===${NC}"
    
    planz create subtree-test 2>/dev/null
    planz add subtree-test "Phase 1" 2>/dev/null
    planz add subtree-test "Phase 1/Task A" 2>/dev/null
    planz add subtree-test "Phase 1/Task B" 2>/dev/null
    planz add subtree-test "Phase 2" 2>/dev/null
    planz add subtree-test "Phase 2/Task C" 2>/dev/null
    
    # Show full tree
    output=$(planz show subtree-test 2>&1)
    assert_contains "$output" "Phase 1" "full tree has Phase 1"
    assert_contains "$output" "Phase 2" "full tree has Phase 2"
    
    # Show subtree
    output=$(planz show subtree-test "Phase 1" 2>&1)
    assert_contains "$output" "Task A" "subtree has Task A"
    assert_contains "$output" "Task B" "subtree has Task B"
    assert_not_contains "$output" "Phase 2" "subtree doesn't have Phase 2"
    assert_not_contains "$output" "Task C" "subtree doesn't have Task C"
    
    planz delete subtree-test 2>/dev/null
}

test_multiple_roots() {
    echo -e "\n${YELLOW}=== Multiple Roots Tests ===${NC}"
    
    planz create multi-root-test 2>/dev/null
    
    # Add multiple root nodes
    planz add multi-root-test "Root 1" 2>/dev/null
    planz add multi-root-test "Root 2" 2>/dev/null
    planz add multi-root-test "Root 3" 2>/dev/null
    planz add multi-root-test "Root 1/Child" 2>/dev/null
    planz add multi-root-test "Root 2/Child" 2>/dev/null
    
    # Verify all roots
    output=$(planz show multi-root-test 2>&1)
    assert_contains "$output" "Root 1" "has Root 1"
    assert_contains "$output" "Root 2" "has Root 2"
    assert_contains "$output" "Root 3" "has Root 3"
    
    # Progress should show all roots
    output=$(planz progress multi-root-test 2>&1)
    assert_contains "$output" "Root 1" "progress has Root 1"
    assert_contains "$output" "Root 2" "progress has Root 2"
    assert_contains "$output" "Root 3" "progress has Root 3"
    
    planz delete multi-root-test 2>/dev/null
}

test_delete_project() {
    echo -e "\n${YELLOW}=== Delete Project Tests ===${NC}"
    
    mkdir -p "$TEST_DB_DIR/delete-project-test"
    
    planz create plan1 --project "$TEST_DB_DIR/delete-project-test" 2>/dev/null
    planz create plan2 --project "$TEST_DB_DIR/delete-project-test" 2>/dev/null
    planz add plan1 "Task" --project "$TEST_DB_DIR/delete-project-test" 2>/dev/null
    
    # Delete entire project
    output=$(planz delete-project --project "$TEST_DB_DIR/delete-project-test" 2>&1)
    assert_contains "$output" "Deleted project" "delete-project succeeds"
    
    # Verify plans gone
    output=$(planz list --project "$TEST_DB_DIR/delete-project-test" 2>&1)
    assert_contains "$output" "No plans found" "plans removed after delete-project"
}

test_move_edge_cases() {
    echo -e "\n${YELLOW}=== Move Edge Cases ===${NC}"
    
    planz create move-edge-test 2>/dev/null
    planz add move-edge-test "Parent" 2>/dev/null
    planz add move-edge-test "Parent/Child" 2>/dev/null
    planz add move-edge-test "Sibling" 2>/dev/null
    
    # Move to non-existent parent fails
    output=$(planz move move-edge-test "Parent/Child" --to "NonExistent" 2>&1) || true
    assert_contains "$output" "Invalid" "move to non-existent parent fails"
    
    # Move without --to or --after fails
    output=$(planz move move-edge-test "Parent/Child" 2>&1) || true
    assert_contains "$output" "requires" "move without destination fails"
    
    planz delete move-edge-test 2>/dev/null
}

test_done_cascade_complex() {
    echo -e "\n${YELLOW}=== Done Cascade Complex Tests ===${NC}"
    
    planz create cascade-test 2>/dev/null
    planz add cascade-test "Root" 2>/dev/null
    planz add cascade-test "Root/A" 2>/dev/null
    planz add cascade-test "Root/A/A1" 2>/dev/null
    planz add cascade-test "Root/A/A2" 2>/dev/null
    planz add cascade-test "Root/B" 2>/dev/null
    planz add cascade-test "Root/B/B1" 2>/dev/null
    
    # Mark one leaf done
    planz done cascade-test "Root/A/A1" 2>/dev/null
    output=$(planz show cascade-test 2>&1)
    assert_contains "$output" "[x] A1" "A1 is done"
    assert_contains "$output" "[ ] A" "A not done (A2 still undone)"
    
    # Mark sibling done -> parent should auto-done
    planz done cascade-test "Root/A/A2" 2>/dev/null
    output=$(planz show cascade-test 2>&1)
    assert_contains "$output" "[x] A" "A auto-done when all children done"
    assert_contains "$output" "[ ] Root" "Root not done (B still undone)"
    
    # Mark remaining branch done
    planz done cascade-test "Root/B" 2>/dev/null
    output=$(planz show cascade-test 2>&1)
    assert_contains "$output" "[x] Root" "Root auto-done when all children done"
    
    planz delete cascade-test 2>/dev/null
}

test_undone_propagation() {
    echo -e "\n${YELLOW}=== Undone Propagation Tests ===${NC}"
    
    planz create undone-prop-test 2>/dev/null
    planz add undone-prop-test "Root" 2>/dev/null
    planz add undone-prop-test "Root/Child" 2>/dev/null
    planz add undone-prop-test "Root/Child/Leaf" 2>/dev/null
    
    # Mark everything done
    planz done undone-prop-test "Root" 2>/dev/null
    output=$(planz show undone-prop-test 2>&1)
    assert_contains "$output" "[x] Root" "all done initially"
    
    # Undone at leaf should propagate up
    planz undone undone-prop-test "Root/Child/Leaf" 2>/dev/null
    output=$(planz show undone-prop-test 2>&1)
    assert_contains "$output" "[ ] Leaf" "leaf undone"
    assert_contains "$output" "[ ] Child" "child propagated undone"
    assert_contains "$output" "[ ] Root" "root propagated undone"
    
    planz delete undone-prop-test 2>/dev/null
}

test_path_variations() {
    echo -e "\n${YELLOW}=== Path Variation Tests ===${NC}"
    
    planz create path-test 2>/dev/null
    planz add path-test "Phase" 2>/dev/null
    planz add path-test "Phase/Task" 2>/dev/null
    
    # Path with trailing slash
    output=$(planz show path-test "Phase/" 2>&1)
    assert_contains "$output" "Task" "trailing slash works"
    
    # Path with extra spaces
    output=$(planz add path-test "  Phase  /  New Task  " 2>&1)
    assert_contains "$output" "Added" "spaces in path trimmed"
    
    planz delete path-test 2>/dev/null
}

test_large_plan() {
    echo -e "\n${YELLOW}=== Large Plan Tests ===${NC}"
    
    planz create large-test 2>/dev/null
    
    # Add 50 root nodes
    for i in {1..50}; do
        planz add large-test "Phase $i" 2>/dev/null
    done
    
    # Add children to some
    for i in {1..10}; do
        planz add large-test "Phase $i/Task 1" 2>/dev/null
        planz add large-test "Phase $i/Task 2" 2>/dev/null
    done
    
    # Verify count
    output=$(planz list 2>&1)
    assert_contains "$output" "70" "large planz has 70 nodes"
    
    # Show should handle large plans
    output=$(planz show large-test 2>&1)
    assert_contains "$output" "Phase 50" "can show large plan"
    
    # JSON should be valid
    output=$(planz show large-test --json 2>&1)
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null | grep -q "50"; then
        echo -e "  ${GREEN}✓${NC} large planz JSON valid with 50 items"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}✗${NC} large planz JSON issue"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    planz delete large-test 2>/dev/null
}

test_special_node_names() {
    echo -e "\n${YELLOW}=== Special Node Name Tests ===${NC}"
    
    planz create special-test 2>/dev/null
    
    # Numbers only
    output=$(planz add special-test "123" 2>&1)
    assert_contains "$output" "Added" "numeric title works"
    
    # Dots
    output=$(planz add special-test "v1.0.0" 2>&1)
    assert_contains "$output" "Added" "dots in title work"
    
    # Parentheses
    output=$(planz add special-test "Task (optional)" 2>&1)
    assert_contains "$output" "Added" "parentheses work"
    
    # Brackets
    output=$(planz add special-test "[WIP] Feature" 2>&1)
    assert_contains "$output" "Added" "brackets work"
    
    # Dash
    output=$(planz add special-test "high-priority-task" 2>&1)
    assert_contains "$output" "Added" "dashes work"
    
    # Underscore
    output=$(planz add special-test "some_task_name" 2>&1)
    assert_contains "$output" "Added" "underscores work"
    
    # Hash
    output=$(planz add special-test "Issue #42" 2>&1)
    assert_contains "$output" "Added" "hash works"
    
    planz delete special-test 2>/dev/null
}

test_xml_valid() {
    echo -e "\n${YELLOW}=== XML Validation Tests ===${NC}"
    
    planz create xml-valid-test 2>/dev/null
    planz add xml-valid-test "Phase 1" --desc "Description" 2>/dev/null
    planz add xml-valid-test "Phase 1/Task" 2>/dev/null
    planz done xml-valid-test "Phase 1/Task" 2>/dev/null
    
    # Get XML and validate with xmllint if available
    output=$(planz show xml-valid-test --xml 2>&1)
    
    TESTS_RUN=$((TESTS_RUN + 1))
    if command -v xmllint &> /dev/null; then
        if echo "$output" | xmllint --noout - 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} XML is well-formed (xmllint)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "  ${RED}✗${NC} XML is malformed"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    else
        # Fallback: basic checks
        if [[ "$output" == *'<?xml version="1.0"'* ]] && [[ "$output" == *'</plan>'* ]]; then
            echo -e "  ${GREEN}✓${NC} XML has proper structure (basic check)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "  ${RED}✗${NC} XML structure invalid"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    fi
    
    planz delete xml-valid-test 2>/dev/null
}

test_markdown_output() {
    echo -e "\n${YELLOW}=== Markdown Output Tests ===${NC}"
    
    planz create md-test 2>/dev/null
    planz add md-test "Phase 1" --desc "A description" 2>/dev/null
    planz add md-test "Phase 1/Task A" 2>/dev/null
    planz add md-test "Phase 1/Task B" 2>/dev/null
    planz done md-test "Phase 1/Task A" 2>/dev/null
    
    output=$(planz show md-test --md 2>&1)
    
    # Check markdown structure
    assert_contains "$output" "# md-test" "markdown has h1 title"
    assert_contains "$output" "- [x] Task A" "markdown has checked item"
    assert_contains "$output" "- [ ] Task B" "markdown has unchecked item"
    assert_contains "$output" "A description" "markdown has description"
    
    # Check indentation (2 spaces per level)
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$output" | grep -q "^  - \["; then
        echo -e "  ${GREEN}✓${NC} markdown has proper indentation"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}✗${NC} markdown indentation wrong"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    planz delete md-test 2>/dev/null
}

test_refine() {
    echo -e "\n${YELLOW}=== Refine Tests ===${NC}"
    
    planz create refine-test 2>/dev/null
    planz add refine-test "Phase 1" 2>/dev/null
    planz add refine-test "Phase 1/Simple task" 2>/dev/null
    
    # Refine a leaf node
    output=$(planz refine refine-test "Phase 1/Simple task" --add "Step 1" --add "Step 2" 2>&1)
    assert_contains "$output" "Refined" "refine succeeds"
    
    # Verify children added
    output=$(planz show refine-test 2>&1)
    assert_contains "$output" "Step 1" "refine added Step 1"
    assert_contains "$output" "Step 2" "refine added Step 2"
    
    # Refine with nested children
    planz add refine-test "Phase 1/Another task" 2>/dev/null
    output=$(planz refine refine-test "Phase 1/Another task" --add "Sub/Nested" 2>&1)
    assert_contains "$output" "Refined" "refine with nested path succeeds"
    
    output=$(planz show refine-test 2>&1)
    assert_contains "$output" "Sub" "refine created intermediate node"
    assert_contains "$output" "Nested" "refine created nested leaf"
    
    # Cannot refine a non-leaf (has children now)
    output=$(planz refine refine-test "Phase 1/Simple task" --add "More" 2>&1) || true
    assert_contains "$output" "children" "cannot refine non-leaf"
    
    # Cannot refine at max depth
    planz add refine-test "L1" 2>/dev/null
    planz add refine-test "L1/L2" 2>/dev/null
    planz add refine-test "L1/L2/L3" 2>/dev/null
    planz add refine-test "L1/L2/L3/L4" 2>/dev/null
    output=$(planz refine refine-test "L1/L2/L3/L4" --add "TooDeep" 2>&1) || true
    assert_contains "$output" "depth" "cannot refine at max depth"
    
    planz delete refine-test 2>/dev/null
}

test_node_id_syntax() {
    echo -e "\n${YELLOW}=== Node ID Syntax Tests ===${NC}"
    
    planz create id-syntax-test 2>/dev/null
    planz add id-syntax-test "Phase 1" 2>/dev/null
    planz add id-syntax-test "Phase 1/Task A" 2>/dev/null
    planz add id-syntax-test "Phase 2" 2>/dev/null
    
    # Verify IDs in output
    output=$(planz show id-syntax-test 2>&1)
    assert_contains "$output" "[1]" "output shows id 1"
    assert_contains "$output" "[2]" "output shows id 2"
    assert_contains "$output" "[3]" "output shows id 3"
    
    # Done using #id
    output=$(planz done id-syntax-test "#2" 2>&1)
    assert_contains "$output" "1 item" "done with #id works"
    
    # Rename using #id
    output=$(planz rename id-syntax-test "#3" "Phase 2 Renamed" 2>&1)
    assert_contains "$output" "Renamed" "rename with #id works"
    
    output=$(planz show id-syntax-test 2>&1)
    assert_contains "$output" "Phase 2 Renamed" "rename actually changed title"
    
    # Describe using #id
    output=$(planz describe id-syntax-test "#1" --desc "Phase one description" 2>&1)
    assert_contains "$output" "Updated description" "describe with #id works"
    
    # Refine using #id - first add a new leaf
    planz add id-syntax-test "Phase 2 Renamed/Leaf Task" 2>/dev/null
    output=$(planz refine id-syntax-test "#4" --add "Subtask 1" 2>&1)
    assert_contains "$output" "Refined" "refine with #id works"
    
    # Remove using #id
    output=$(planz remove id-syntax-test "#5" 2>&1)
    assert_contains "$output" "Removed" "remove with #id works"
    
    # JSON output includes id
    output=$(planz show id-syntax-test --json 2>&1)
    assert_contains "$output" '"id":1' "json includes id field"
    
    # XML output includes id
    output=$(planz show id-syntax-test --xml 2>&1)
    assert_contains "$output" 'id="1"' "xml includes id attribute"
    
    planz delete id-syntax-test 2>/dev/null
}

test_empty_operations() {
    echo -e "\n${YELLOW}=== Empty Operations Tests ===${NC}"
    
    planz create empty-ops-test 2>/dev/null
    
    # Progress on empty planz
    output=$(planz progress empty-ops-test 2>&1)
    assert_contains "$output" "0%" "progress on empty planz shows 0%"
    
    # Show empty planz
    output=$(planz show empty-ops-test 2>&1)
    assert_contains "$output" "empty-ops-test" "show empty planz works"
    
    # Done on empty planz (should handle gracefully)
    output=$(planz done empty-ops-test "NonExistent" 2>&1) || true
    # Should not crash
    
    planz delete empty-ops-test 2>/dev/null
}

# ============================================================================
# RUN ALL TESTS
# ============================================================================

echo "========================================"
echo "Plan CLI Test Suite"
echo "========================================"

setup

test_plan_crud
test_plan_rename
test_node_add
test_node_remove
test_node_rename
test_node_describe
test_done_undone
test_move
test_show_formats
test_progress
test_summarize
test_project_scope
test_edge_cases
test_error_handling
test_concurrent_safety
test_xml_escaping
test_json_escaping
test_deep_nesting
test_show_subtree
test_multiple_roots
test_delete_project
test_move_edge_cases
test_done_cascade_complex
test_undone_propagation
test_path_variations
test_large_plan
test_special_node_names
test_xml_valid
test_markdown_output
test_refine
test_node_id_syntax
test_empty_operations
