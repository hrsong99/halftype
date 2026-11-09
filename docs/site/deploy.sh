#!/bin/zsh
# Publishes the landing page (docs/site/a2) to https://halftype.app: copies it to js, where the Dokploy compose
# "halftype-site" serves /home/ubuntu/halftype-site/html with nginx. No rebuild needed; nginx serves the new files at once.
set -euo pipefail
cd "${0:A:h}"
rsync -az --delete --exclude .taste-skill --exclude shots --exclude .gitignore --chmod=a+rX a2/ js:halftype-site/html/
rsync -az --chmod=a+r nginx.conf js:halftype-site/nginx.conf
ssh js 'chmod -R a+rX halftype-site'  # rsync keeps a file's own mode; an owner-only image is a 403 behind nginx
echo "deployed: https://halftype.app/"
