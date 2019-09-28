#!/bin/bash

set -euo pipefail

channel="$1"

IRSSICONF="servers = (
  {
    address = 'irc.twitch.tv';
    chatnet = 'Twitch';
    port = '6697';
    password = 'oauth:46sh4wje1xxvkejs1z9peqrs5ld6r4';
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
    nick = 'whimsicaltraveler2463';
  }
}

ignores = {
  {
    level = 'JOIN PARTS QUITS';
  }
}"


streamlink --player mpv https://www.twitch.tv/$1 best >> /dev/null 2>&1 &
irssi --config <(echo "$IRSSICONF")
