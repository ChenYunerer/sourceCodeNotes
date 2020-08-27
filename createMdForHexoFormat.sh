#!/bin/bash
mdName="$1"
time=$(date "+%Y-%m-%d %H:%M:%S")
touch ${mdName}.md
echo "---
title: ${mdName}
data: ${time}
---
# ${mdName}
" > ${mdName}.md