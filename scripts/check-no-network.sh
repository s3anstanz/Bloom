#!/bin/bash
# Fails when BloomCore references a networking API or a web address. Bloom processes files on this Mac only.
set -euo pipefail

cd "$(dirname "$0")/.."
pattern='URLSession|URLRequest|NSURLConnection|NWConnection|NWListener|NWBrowser|import Network|CFNetwork|CFSocket|CFStream|getaddrinfo|https?://'

if matches="$(grep -rnE "$pattern" Sources/BloomCore)"; then
  echo "BloomCore must not use the network. Found:"
  echo "$matches"
  exit 1
fi
echo "No networking APIs in BloomCore."
