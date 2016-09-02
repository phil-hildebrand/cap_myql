#! /bin/bash
#set -x
count=25
while [ $count -gt 0 ]   
do
        STATUS=`mysql -e 'show slave status\G' | grep Running | grep -i No | wc -l`
        let count-=1
        if [ $STATUS -gt 0 ]
        then
                echo "Slave Not Running [$STATUS]"
                mysql -v < /root/skip.sql
        else
                echo "Slave is Running [$STATUS]"
                mysql -e 'show slave status\G' | grep -i Seconds
        fi
        sleep 2
done
