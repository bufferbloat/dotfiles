#!/bin/bash

if ping -c 1 -W 2 ping.2264.pw > /dev/null 2>&1; then
    echo 'vps: <span foreground="#a6e3a1">up</span>'
else
    echo 'vps: <span foreground="#f38ba8">down</span>'
fi
