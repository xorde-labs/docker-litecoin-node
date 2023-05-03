#!/bin/sh

litecoind --version | awk 'NF{ print $NF }' | head -n 1
