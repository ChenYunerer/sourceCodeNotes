#!/bin/bash
cp -rf ./* /Users/yuner/WorkSpace/hexo/blog/source/_posts
cd /Users/yuner/WorkSpace/hexo/blog
hexo clean
hexo g
echo 'blog.yuner.fun' > ./public/CNAME
hexo d