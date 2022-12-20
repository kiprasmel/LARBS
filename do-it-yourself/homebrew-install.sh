#!/bin/sh

brew bundle install

echo "\


custom: to use real gcc/g++ instead of clang,
create a symlink in your prefix dir (/usr/local/bin on intel mac,
and /opt/homebrew/bin) for executables, like so:

assuming latest gcc/g++ version 12:

intel mac:

ln -s /usr/local/bin/gcc-12 /usr/local/bin/gcc
ln -s /usr/local/bin/g++-12 /usr/local/bin/g++

M1 mac:

ln -s /opt/homebrew/bin/gcc-12 /usr/local/bin/gcc
ln -s /opt/homebrew/bin/g++-12 /usr/local/bin/g++

"

