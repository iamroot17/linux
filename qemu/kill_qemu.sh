#!/bin/bash

kill -9 $(ps -ef | grep qemu-system-aarch64 | grep -v grep | awk '{print $2}')
