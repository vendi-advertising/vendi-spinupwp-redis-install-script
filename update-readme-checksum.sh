#!/usr/bin/env bash

# Generate checksum for the script
CHECKSUM=$(sha256sum install-redis-per-site.sh | awk '{print $1}')

# Update README with the checksum
sed -i "/## SHA256 Checksum/,/\`\`\`/c\\
## SHA256 Checksum\\
\\
For the latest release, verify the script's SHA256 checksum matches:\\
\\
\`\`\`\\
${CHECKSUM}  install-redis-per-site.sh\\
\`\`\`" README.md

echo "Updated README.md with checksum: ${CHECKSUM}"
