#!/bin/bash
# watch a twitch stream via mpv and irssi
# requires streamlink, mpv, irssi, a client_id and an oauth
# usage: twitch.sh channelname
# irssi does not automatically switch to the channel, type /window 2 to focus it.

if [ -z "$1" ];then echo "Usage $0 channelname"; exit 1; fi

channel="$1"

# python script to check if the streamer is live via twitch api
# the client_id is per app, this one i found on google via
# twitch client id site:pastebin.com
STATUS="#!/usr/bin/env python3

import json
import requests

client_id = 'whnghno3rybgm9wp6bl97vwu43d2qo'
link = 'https://api.twitch.tv/helix/streams?user_login=' + '$1'
accept = 'application/vnd.twitchtv.v5+json'

r = requests.get(link, headers={'Client-ID':client_id, 'Accept': accept})

resp_dict = json.loads(r.text)

for i in resp_dict:
    if i == 'data' and len(resp_dict[i]) > 0:
        print(resp_dict['data'][0]['type'])"

IRSSICONF="servers = (
  {
    address = 'irc.twitch.tv';
    chatnet = 'Twitch';
    port = '6697';
    password = 'oauth:YOUROAUTH';
    use_ssl = 'yes';
    ssl_verify = 'no';
    autoconnect = 'yes';
  },
);

chatnets = {
  twitch = {
    type = 'IRC';
    autosendcmd = '/quote CAP REQ :twitch.tv/membership';
  };
}

channels = (
  { name = '$channel'; chatnet = 'twitch'; autojoin = 'yes'; },
);

settings = {
  core = {
    nick = 'YOURNICK';
  }
}

ignores = {
  {
    level = 'JOIN PARTS QUITS';
  }
}"


status=$(python3 <(echo "$STATUS"))

if [ -z $status ];then echo "Error: user is not streaming right now"; exit 1; fi

streamlink --player mpv https://www.twitch.tv/$1 best >> /dev/null 2>&1 &
irssi --config <(echo "$IRSSICONF")
