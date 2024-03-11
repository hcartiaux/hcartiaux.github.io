#!/bin/sh

# If a command fails then the deploy stops
set -e

printf "\033[0;32mDeploying updates to GitHub...\033[0m\n"

git submodule update --init

# Go To Public folder
cd public
git rm -rf *

cd ..
# Build the project.
hugo -t solar-theme-hugo # if using a theme, replace with `hugo -t <YOURTHEME>`
cd public

# Add changes to git.
git add .

# Commit changes.
msg="rebuilding site $(date)"
if [ -n "$*" ]; then
	msg="$*"
fi
git commit -m "$msg"

# Push source and build repos.
git push origin master

cd ..

# Submodule update
git commit -m "$msg" public
git push origin master
