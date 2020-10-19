#!/bin/bash
rm -rf /Users/yuner/WorkSpace/hexo/blog/source/_posts/*
mkdir -p /Users/yuner/WorkSpace/hexo/blog/source/_posts
cp -rfp ./* /Users/yuner/WorkSpace/hexo/blog/source/_posts
cd /Users/yuner/WorkSpace/hexo/blog
hexo clean
hexo g
echo 'blog.yuner.fun' > ./public/CNAME
hexo d
