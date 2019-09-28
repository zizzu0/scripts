#!/bin/bash
# watch a twitch stream via mpv and irssi
# requires streamlink, mpv, irssi
# usage: twitch.sh channelname
# irssi does not automatically switch to the channel, type /window 2 to focus it.

set -euo pipefail

channel="$1"

IRSSICONF="servers = (
  {
    address = 'irc.twitch.tv';
    chatnet = 'Twitch';
    port = '6697';
    password = 'oauth:youroauthhere';
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
    nick = 'yournicknamehere';
  }
}

ignores = {
  {
    level = 'JOIN PARTS QUITS';
  }
}"


streamlink --player mpv https://www.twitch.tv/$1 best >> /dev/null 2>&1 &
irssi --config <(echo "$IRSSICONF")
