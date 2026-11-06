#!/bin/sh
set -eu

cd /var/www/html
if [ -d ".git" ]; then
  echo "Git repository found. Pulling latest changes..."
  git pull
else
  echo "Not a git repository. Initializing ..."
  git init
  git remote add origin https://github.com/geerlingguy/shelly-plug-prometheus.git
  git fetch origin
  git checkout origin/master -ft
fi
