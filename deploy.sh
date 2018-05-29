#!/bin/sh

DIR=$(pwd)
cd $(dirname $0)
WORKDIR=$(pwd)

docker run --rm -it -v "$WORKDIR/..:/source" -w "/source" forlanua/nim /bin/sh -c "nimble install && cd tests && nake tests"

RESULT=$?
if [ "$RESULT" != "0" ]; then
    exit $RESULT
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "master" ]; then
    echo "Non master branch \`$BRANCH\`"
    exit 0
fi

set -f

mkdir -p ~/.ssh
echo $GITHUB_KEY > ~/.ssh/id_rsa
chmod 400 ~/.ssh/id_rsa

git config --global user.email "builds@travis-ci.com"
git config --global user.name "Travis CI"

git tag -l | xargs git tag -d
git fetch --tags


OLDTAG=
for tag in $(git tag --list 'v*' --sort=-v:refname); do
    OLDTAG="$tag"
    break
done

echo "Old tag: $OLDTAG"

PARTS=(${OLDTAG//\./ })
NEWTAG="${PARTS[0]}.${PARTS[1]}.$((${PARTS[2]}+1))"
DATE=$(date -u +"%F %H:%M:%S UTC")
MESSAGE="Release date $DATE"

git tag -a "$NEWTAG" -m "$MESSAGE"

echo "New tag: $NEWTAG. With message \`$MESSAGE\`"

git push --tags