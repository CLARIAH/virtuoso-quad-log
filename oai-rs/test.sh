#!/bin/sh

cd /usr/src/app

ls -l ./sample/

./resource-list.py --resource-url http://example.com/res --resource-dir ./sample

echo "\n\n./sample/resource-list.xml\n---\n"
cat ./sample/resource-list.xml

echo "\n\n./sample/capability-list.xml\n---\n"
cat ./sample/capability-list.xml

echo "\n\n./sample/resourcesync\n---\n"
cat ./sample/resourcesync

echo "\n"
ls -l ./sample/