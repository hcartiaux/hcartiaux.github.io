#!/bin/sh

# If a command fails then the deploy stops
set -e

printf "\033[0;32mDeploying updates to GitHub...\033[0m\n"

# Submodule update
git submodule update --init

# Build the project.
hugo --cleanDestinationDir

# Add changes to git.
git add public

# Commit changes.
msg="rebuilding site $(date)"
if [ -n "$*" ]; then
       msg="$*"
fi
git commit -m "$msg"

# Push source and build repos.
git push origin master

