# Recommended Hooks for Kiro-CoCo

These hooks add safety guardrails when running AWS CLI commands during kiro-coco
integrations. They are optional but strongly recommended.

---

## aws-profile-guard

**What it does:** Blocks any `aws` CLI command that is missing `--profile`, then lists
all available profiles so you can re-run with the correct one. Prevents silent
operations against the wrong AWS account.

**Allows through:**
- Non-`aws` commands (passthrough)
- `aws --version` and `aws configure` (no profile needed)
- Commands that already include `--profile`
- Commands that set `AWS_PROFILE` or `AWS_DEFAULT_PROFILE` as env vars

---

### Step 1: Save the hook script

Save this script to your machine. A conventional location is `~/.kiro/hooks/scripts/`:

```bash
mkdir -p ~/.kiro/hooks/scripts
```

```bash
#!/bin/bash
# aws-profile-guard.sh
# Blocks aws CLI commands missing --profile to prevent wrong-account operations.

INPUT=$(cat)

# Extract bash command from JSON tool input
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Fallback to python3 if jq is unavailable
if [ -z "$COMMAND" ]; then
    COMMAND=$(echo "$INPUT" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" \
        2>/dev/null)
fi

# Not an aws command — allow
if ! echo "$COMMAND" | grep -qE '(^|;|\||\&)\s*aws\s+'; then
    exit 0
fi

# Informational / setup commands that don't need a profile — allow
if echo "$COMMAND" | grep -qE 'aws\s+(--version|configure)'; then
    exit 0
fi

# Profile already specified — allow
if echo "$COMMAND" | grep -qE '(--profile|AWS_PROFILE=|AWS_DEFAULT_PROFILE=)'; then
    exit 0
fi

# Missing --profile — list available profiles and block
echo "AWS command is missing --profile. Specify one explicitly to avoid hitting the wrong account."
echo ""
echo "Available AWS profiles:"
PROFILES=$({
    grep '^\[' "${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}" 2>/dev/null | tr -d '[]'
    grep '^\[profile ' "${AWS_CONFIG_FILE:-$HOME/.aws/config}" 2>/dev/null | sed 's/\[profile //;s/\]//'
    grep '^\[default\]' "${AWS_CONFIG_FILE:-$HOME/.aws/config}" 2>/dev/null | tr -d '[]'
} | sort -u)
if [ -n "$PROFILES" ]; then
    echo "$PROFILES" | sed 's/^/  /'
else
    echo "  (none found — run 'aws configure --profile <name>' to set one up)"
fi
echo ""
echo "Re-run your command with: --profile <profile-name>"
exit 2
```

Make it executable:
```bash
chmod +x ~/.kiro/hooks/scripts/aws-profile-guard.sh
```

---

### Step 2: Register the hook in your Kiro workspace

Create `.kiro/hooks/aws-profile-guard.yaml` in your project workspace:

```yaml
name: aws-profile-guard
description: Block AWS CLI commands missing --profile to prevent wrong-account operations
trigger: pre-tool-use
tools:
  - bash
command: ~/.kiro/hooks/scripts/aws-profile-guard.sh
```

> **Note:** Verify the exact YAML schema against your Kiro version's hook documentation,
> as the format may vary. The script itself is stable across versions.

---

### For Claude Code users

If you use Claude Code instead of (or alongside) Kiro, register the same script via
`~/.claude/settings.json` (global) or `.claude/settings.json` (project-level):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.kiro/hooks/scripts/aws-profile-guard.sh"
          }
        ]
      }
    ]
  }
}
```

The same script file works for both tools — only the registration differs.

---

### Verification

Test the hook directly to confirm it behaves correctly before relying on it:

```bash
# Should ALLOW (exit 0) — non-aws command
echo '{"tool_input":{"command":"ls -la"}}' | ~/.kiro/hooks/scripts/aws-profile-guard.sh
echo "exit: $?"

# Should ALLOW (exit 0) — profile present
echo '{"tool_input":{"command":"aws kinesis list-streams --profile my-profile --region us-east-1"}}' \
  | ~/.kiro/hooks/scripts/aws-profile-guard.sh
echo "exit: $?"

# Should BLOCK (exit 2) — missing profile
echo '{"tool_input":{"command":"aws kinesis list-streams --region us-east-1"}}' \
  | ~/.kiro/hooks/scripts/aws-profile-guard.sh
echo "exit: $?"
```
