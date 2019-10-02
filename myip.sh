#!/bin/bash
# 100% bash ip grabber, no external commands

# 3 is a new file descriptor associated with a socket (0 is stdin, 1 is stdout, 2 is stderr)
# open for read < and write >
exec 3<>/dev/tcp/ifconfig.co/80
echo -e "GET / HTTP/1.1\r\nhost: ifconfig.co\r\nConnection: close\r\n\r\n" >&3

ip=""
while read -u 3 -r line
do
  if [[ $line =~ 'class="ip"' ]];then ip=$line;break;fi
done
 
if [ -z "$ip" ];then echo "failed to fetch ip";exit 1;fi

pattern="[0-9].*[0-9]"
[[ $ip =~ $pattern ]] && echo "${BASH_REMATCH}"
