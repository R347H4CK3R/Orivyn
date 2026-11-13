#!/bin/sh
xsetroot -solid '#233e50'
xterm -title 'Orivyn isolated guest' -geometry 74x16+30+40 -e /usr/bin/orivyn-ready-shell &
exec fluxbox
