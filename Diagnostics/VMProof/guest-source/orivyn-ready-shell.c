/* Original Orivyn guest readiness helper. SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Christopher Nickel
 * Permission is granted, free of charge, to any person obtaining a copy to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell this software,
 * provided this notice is included. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT
 * WARRANTY OF ANY KIND. IN NO EVENT SHALL AUTHORS BE LIABLE FOR ANY CLAIM.
 * Reports readiness only for this local X terminal when mapped and focused.
 * Never interprets guest output as host actions or launches an external service.
 */
#define _POSIX_C_SOURCE 200809L
#include <X11/Xlib.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
static int xfailed;
static int xerror(Display *d, XErrorEvent *e) { (void)d; (void)e; xfailed=1; return 0; }
static int owns_focus(Display *d, Window wanted) {
    Window focus, root, parent, *children=NULL; unsigned count; int revert;
    XGetInputFocus(d,&focus,&revert);
    for (unsigned depth=0; depth<32 && focus!=None && focus!=PointerRoot; depth++) {
        if (focus==wanted) return !xfailed;
        if (!XQueryTree(d,focus,&root,&parent,&children,&count)) return 0;
        if (children) XFree(children);
        children=NULL;
        if (parent==focus || focus==root) return 0;
        focus=parent;
    }
    return 0;
}
static int ready(void) {
    const char *display=getenv("DISPLAY"), *id=getenv("WINDOWID"); char *end;
    if (!display || (strcmp(display,":0") && strcmp(display,":0.0")) || !id || !*id) return 0;
    errno=0; unsigned long window=strtoul(id,&end,10);
    if (errno || *end || !window) return 0;
    Display *d=XOpenDisplay(display); if (!d) return 0;
    XSetErrorHandler(xerror);
    struct timespec began, now, pause={0,100000000}; clock_gettime(CLOCK_MONOTONIC,&began);
    int ok=0;
    do {
        XWindowAttributes attributes; xfailed=0;
        if (XGetWindowAttributes(d,(Window)window,&attributes) && attributes.map_state==IsViewable && owns_focus(d,(Window)window) && !xfailed) { ok=1; break; }
        nanosleep(&pause,NULL); clock_gettime(CLOCK_MONOTONIC,&now);
    } while (now.tv_sec-began.tv_sec<120);
    XCloseDisplay(d); return ok;
}
int main(void) {
    if (ready()) {
        int fd=open("/dev/ttyS0",O_WRONLY|O_NOCTTY);
        if (fd>=0) {
            static const char marker[]="\nORIVYN_DESKTOP_SHELL_READY_v1\n";
            size_t n=0; while(n<sizeof(marker)-1) { ssize_t w=write(fd,marker+n,sizeof(marker)-1-n); if(w<0 && errno==EINTR) continue; if(w<=0) break; n+=(size_t)w; }
            close(fd);
        }
    } else fprintf(stderr,"Graphical terminal readiness timed out; click terminal to use shell.\n");
    char *const args[]={"/bin/sh",NULL}; execv("/bin/sh",args); perror("shell exec"); return 127;
}
