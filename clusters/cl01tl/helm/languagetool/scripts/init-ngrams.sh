#!/bin/sh
set -eu

echo ">> Checking N-grams status..."
if [ -d "/ngrams/en/1grams" ] && [ -d "/ngrams/en/2grams" ] && [ -d "/ngrams/en/3grams" ]; then
  echo ">> N-grams are already unpacked and initialized. Skipping download."
  exit 0
fi

echo ">> N-grams missing. Starting provisioning sequence..."
mkdir -p /ngrams
cd /ngrams

ARCHIVE="ngrams-en-20150817.zip"
URL="https://languagetool.org/download/ngram-data/${ARCHIVE}"

echo ">> Downloading English N-grams archive from ${URL}..."
rm -f "${ARCHIVE}"
wget -O "${ARCHIVE}" "${URL}"

echo ">> Extracting archive (this will take a while)..."
unzip -q -o "${ARCHIVE}"

echo ">> Cleaning up workspace..."
rm -f "${ARCHIVE}"
echo ">> Initialization complete!"
