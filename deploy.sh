#!/bin/bash

if [ $TRAVIS_PULL_REQUEST == "true" ]; then
    exit 0
fi

set -e

rm -rf _site
mkdir _site

git clone https://${GITHUB_TOKEN}@github.com/KovuTheHusky/pokemon-medals.git --branch gh-pages _site

ruby generate.rb
for i in {1..10}; do find . -type f -name "*.png" -exec pngquant --force --skip-if-larger --output {} --speed 1 --strip {} \;; done
bundle exec jekyll build

cd _site
git config user.email "kovuthehusky@gmail.com"
git config user.name "KovuTheHusky"
git add --all
git commit -a -m "Travis #$TRAVIS_BUILD_NUMBER"
git push --force origin gh-pages
