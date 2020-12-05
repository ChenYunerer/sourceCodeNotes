#!/bin/bash
rm -rf /Users/yun/workSpace/hexo/blog/source/_posts/*
mkdir -p /Users/yun/workSpace/hexo/blog/source/_posts
cp -rfp ./*/*.md /Users/yun/workSpace/hexo/blog/source/_posts
cd /Users/yun/workSpace/hexo/blog
hexo clean
hexo g
echo 'blog.yuner.fun' > ./public/CNAME
hexo d
