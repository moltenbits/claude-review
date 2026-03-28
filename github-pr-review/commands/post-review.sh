#!/usr/bin/env bash
# Create a PENDING (draft) PR review using JSON payload.
# The review is only visible to you until you submit it from the GitHub UI.
#
# Usage: ./post-review.sh <pr_number> <json_file> [dry_run|no_confirm]
#
# Examples:
#   ./post-review.sh 6 /tmp/review.json              # Interactive (prompts for confirmation)
#   ./post-review.sh 6 /tmp/review.json dry_run       # Test without posting
#   ./post-review.sh 6 /tmp/review.json no_confirm    # Skip confirmation (used by skill)
#
# JSON format:
# {
#   "commit_id": "abc123...",
#   "body": "Overall message",
#   "comments": [
#     {
#       "path": "path/to/file.ts",
#       "line": 45,
#       "side": "RIGHT",
#       "body": "Comment text\n\n```suggestion\nconst x = 1;\n```"
#     }
#   ]
# }
#
# Note: Any "event" field in the JSON is stripped before posting to ensure
# the review is always created as PENDING. Submit it from the GitHub UI.

set -e

PR_NUMBER="${1:-}"
JSON_FILE="${2:-}"
MODE="${3:-}"  # "dry_run" or "no_confirm"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

if [ -z "$PR_NUMBER" ] || [ -z "$JSON_FILE" ]; then
  echo "Usage: $0 <pr_number> <json_file> [dry_run|no_confirm]"
  echo ""
  echo "Examples:"
  echo "  $0 6 /tmp/review.json              # Interactive"
  echo "  $0 6 /tmp/review.json dry_run       # Test without posting"
  echo "  $0 6 /tmp/review.json no_confirm    # Skip confirmation"
  exit 1
fi

if [ ! -f "$JSON_FILE" ]; then
  echo -e "${RED}Error: File not found: $JSON_FILE${NC}"
  exit 1
fi

echo -e "${BLUE}=== GitHub PR Review Poster ===${NC}"
echo "PR Number: $PR_NUMBER"
echo "JSON File: $JSON_FILE"

if [ "$MODE" = "dry_run" ]; then
  echo -e "${YELLOW}Mode: DRY RUN (will not post)${NC}"
fi
echo ""

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo -e "${YELLOW}Warning: jq not found. Install for better output: brew install jq${NC}"
  echo ""
fi

# Validate JSON first
echo -e "${BLUE}1. Validating JSON...${NC}"
if command -v jq &> /dev/null; then
  if ! jq empty "$JSON_FILE" 2>/dev/null; then
    echo -e "${RED}✗ Invalid JSON${NC}"
    exit 1
  fi
  echo -e "${GREEN}   ✓ JSON is valid${NC}"
else
  # Basic validation without jq - check file starts with '{' (ignoring leading whitespace)
  if ! head -c 1024 "$JSON_FILE" | grep -qm1 '^[[:space:]]*{'; then
    echo -e "${RED}✗ Invalid JSON (file does not start with '{')${NC}"
    exit 1
  fi
  echo -e "${YELLOW}   ⚠ jq not available - JSON structure was NOT fully validated${NC}"
  echo -e "${YELLOW}     Only verified the file begins with '{'. Install jq for proper validation.${NC}"
fi
echo ""

# Show review summary
echo -e "${BLUE}2. Review Summary:${NC}"
if command -v jq &> /dev/null; then
  COMMIT_ID=$(jq -r '.commit_id // "not set"' "$JSON_FILE")
  COMMENT_COUNT=$(jq '.comments | length' "$JSON_FILE")
  BODY_PREVIEW=$(jq -r '.body // "no body"' "$JSON_FILE" | head -c 60)

  echo "   Commit ID: $COMMIT_ID"
  echo "   Comments: $COMMENT_COUNT"
  echo "   Body: $BODY_PREVIEW..."
else
  echo "   (Install jq for detailed summary)"
fi
echo ""

# Show each comment
echo -e "${BLUE}3. Comments to be posted:${NC}"
if command -v jq &> /dev/null; then
  jq -r '.comments[] | "   \(.path):\(.position) - \(.body | gsub("\n"; " ") | .[0:60])..."' "$JSON_FILE"
else
  echo "   (Install jq to see comment details)"
fi
echo ""

# Always creates a PENDING review
echo -e "${BLUE}4. Mode: PENDING (draft review)${NC}"
echo "   Review will be created as a draft. Submit it from the GitHub UI."
if command -v jq &> /dev/null; then
  HAS_EVENT=$(jq -e '.event' "$JSON_FILE" &> /dev/null && echo "yes" || echo "no")
  if [ "$HAS_EVENT" = "yes" ]; then
    echo -e "${YELLOW}   Note: 'event' field found in JSON and will be stripped before posting.${NC}"
  fi
fi
echo ""

# Dry run mode
if [ "$MODE" = "dry_run" ]; then
  echo -e "${YELLOW}=== DRY RUN COMPLETE - Would create a draft review with the above ===${NC}"
  echo ""
  echo "To create the draft review, run:"
  echo "  $0 $PR_NUMBER $JSON_FILE"
  exit 0
fi

# Confirm before posting (skip with no_confirm)
if [ "$MODE" != "no_confirm" ]; then
  echo -e "${YELLOW}Ready to create a draft review on PR #$PR_NUMBER?${NC}"
  echo -n "Type 'yes' to confirm: "
  read -r CONFIRM

  if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled."
    exit 0
  fi
fi
echo ""

# Post the review as PENDING (draft)
echo -e "${BLUE}5. Posting review as PENDING (draft)...${NC}"

# Build the gh api command
API_PATH="repos/:owner/:repo/pulls/$PR_NUMBER/reviews"

# Strip the "event" field from JSON to ensure the review is created as PENDING.
# The user will submit the review manually from the GitHub UI.
if command -v jq &> /dev/null; then
  CLEANED_JSON=$(mktemp)
  jq 'del(.event)' "$JSON_FILE" > "$CLEANED_JSON"
  INPUT_FILE="$CLEANED_JSON"
else
  INPUT_FILE="$JSON_FILE"
  echo -e "${YELLOW}   ⚠ jq not available — cannot strip 'event' field. If the JSON contains an 'event' key, the review will be auto-submitted.${NC}"
fi

# Post with JSON input
# Temporarily disable errexit so we can capture the exit code and handle errors
set +e
RESULT=$(gh api "$API_PATH" \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  --input "$INPUT_FILE" 2>&1)

EXIT_CODE=$?
set -e

if [ $EXIT_CODE -eq 0 ]; then
  # Clean up temp file
  [ -n "${CLEANED_JSON:-}" ] && rm -f "$CLEANED_JSON"

  echo -e "${GREEN}✓ Draft review created successfully!${NC}"
  echo ""

  # Extract review ID and state
  if command -v jq &> /dev/null; then
    REVIEW_ID=$(echo "$RESULT" | jq -r '.id // empty')
    STATE=$(echo "$RESULT" | jq -r '.state // empty')
    HTML_URL=$(echo "$RESULT" | jq -r '.html_url // empty')

    if [ -n "$REVIEW_ID" ]; then
      echo "Review ID: $REVIEW_ID"
      echo "State: $STATE"
    fi

    if [ -n "$HTML_URL" ]; then
      echo ""
      echo -e "${GREEN}Open the PR to review and submit:${NC}"
      echo "  $HTML_URL"
    else
      # Construct the PR URL from the API path
      echo ""
      echo -e "${GREEN}Open the PR on GitHub to review and submit your pending comments.${NC}"
    fi
  else
    echo "Response:"
    echo "$RESULT"
  fi

  echo ""
  echo -e "${YELLOW}Next step: Open the PR on GitHub, review your pending comments, and click 'Submit review'.${NC}"
else
  # Clean up temp file
  [ -n "${CLEANED_JSON:-}" ] && rm -f "$CLEANED_JSON"
  echo -e "${RED}✗ Failed to post review${NC}"
  echo ""
  echo "Error:"
  echo "$RESULT"
  echo ""

  # Check for common errors
  if echo "$RESULT" | grep -q "could not be resolved"; then
    echo -e "${YELLOW}=== Position Error Detected ===${NC}"
    echo ""
    echo "One or more positions could not be resolved in the diff."
    echo ""
    echo "To fix:"
    echo "  1. Validate positions first:"
    echo "     ./commands/validate-review.sh $PR_NUMBER $JSON_FILE"
    echo ""
    echo "  2. Check specific positions:"
    echo "     ./commands/validate-position.sh $PR_NUMBER <file> <position>"
    echo ""
    echo "  3. Recalculate positions:"
    echo "     ./commands/calculate-position.sh $PR_NUMBER <file>"
    exit 1
  fi

  if echo "$RESULT" | grep -q "Expected value to not be null"; then
    echo -e "${YELLOW}=== Null Value Error Detected ===${NC}"
    echo ""
    echo "One or more required fields are null or empty."
    echo "Check that all comments have: path, position, body"
    exit 1
  fi

  exit 1
fi
