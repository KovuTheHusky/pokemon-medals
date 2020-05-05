#!/bin/bash

find . -type f -name "*.png" -exec pngquant --force --skip-if-larger --output {} --speed 1 --strip {} \;
