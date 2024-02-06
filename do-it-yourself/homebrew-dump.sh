#!/bin/sh

#brew bundle dump -f --describe
#brew bundle dump -f --describe --file=- | grep -v vscode > Brewfile
# no vscode since managed separately
brew bundle dump -f --describe --brews --casks --taps --mas --whalebrew

