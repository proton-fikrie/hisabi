#!/bin/bash
# Create PR for Hisabi Phase 6

cd ~/development/hisabi

# Use the token from environment or prompt
if [ -z "$GH_TOKEN" ]; then
    echo "Please enter your GitHub token:"
    read -s GH_TOKEN
    export GH_TOKEN
fi

# Login with token
echo "$GH_TOKEN" | gh auth login --hostname github.com --git-protocol https --with-token

# Verify auth
gh auth status

# Create PR
gh pr create \
  --title "feat: Phase 6 - Financial Intelligence \& Dashboard Enhancements" \
  --body-file .progress/PHASE6_TRACKING.md \
  --base main \
  --head bot-feature

echo "PR created successfully!"