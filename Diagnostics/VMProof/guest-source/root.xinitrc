#!/bin/sh
xsetroot -solid '#233e50'
xterm -title 'Orivyn isolated guest' -geometry 74x16+30+40 -e /bin/sh -c 'printf "\nORIVYN_DESKTOP_SHELL_READY_v1\n" >/dev/ttyS0; exec /bin/sh' &
exec fluxbox
