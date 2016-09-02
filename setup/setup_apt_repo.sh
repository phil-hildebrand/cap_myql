#!/bin/bash

echo "Setup precona repository."

if [ $UID != 0 ]; then
  echo "Run me as root."
  exit
fi

gpg --keyserver  hkp://keys.gnupg.net --recv-keys 1C4CBDCDCD2EFD2A
gpg -a --export CD2EFD2A | apt-key add -

# VERSION = Ubuntu release
. /etc/lsb-release
VERSION="$DISTRIB_CODENAME"

echo "deb http://repo.percona.com/apt VERSION main" | sed "s/VERSION/$VERSION/g" > /etc/apt/sources.list.d/percona.list
echo "deb-src http://repo.percona.com/apt VERSION main" | sed "s/VERSION/$VERSION/g" >> /etc/apt/sources.list.d/percona.list

apt-get update

echo "Suggested: apt-get install percona-server-server-5.5 percona-server-client-5.5"


