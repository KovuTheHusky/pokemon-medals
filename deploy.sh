#!/bin/bash

if [ $TRAVIS_PULL_REQUEST == "true" ]; then
    exit 0
fi

set -e

rm -rf _site
mkdir _site

git clone https://${GITHUB_TOKEN}@github.com/KovuTheHusky/pokemon-medals.git --branch gh-pages _site

ruby generate.rb
bundle exec jekyll build

cd _site
git config user.email "kovuthehusky@gmail.com"
git config user.name "KovuTheHusky"
git add --all
git commit -a -m "Travis #$TRAVIS_BUILD_NUMBER"
git push --force origin gh-pages
