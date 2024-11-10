# mpv-subversive

MPV (v0.38.0+) plugin **for GNU/Linux** that makes it easy to find and load subtitles for the shows you're watching.

[demo.webm](https://github.com/user-attachments/assets/00b0fa29-70e3-4cf9-8637-c21c13af37fb)



This plugin depends on functionality provided by the [AniList API](https://anilist.gitbook.io/anilist-apiv2-docs/overview/graphql) and [Jimaku](https://jimaku.cc/).

The code to display the GUI menu is largely borrowed from [autosubsync-mpv](https://github.com/joaquintorres/autosubsync-mpv)

## Dependencies
- unrar, unzip, 7zip (to extract archives)
- luasocket, luasec (optional, script will fall back on CURL if this isn't present)
- luarocks (optional, to install luasocket and luasec)

Using luasocket/luasec is a bit faster since we can reuse TCP sockets in that case, but CURL should be perfectly usable too.

## Installation
```sh
sudo pacman -Syu unrar unzip p7zip lua51 luarocks
sudo luarocks --lua-version 5.1 install luasocket
sudo luarocks --lua-version 5.1 install luasec
git clone --recurse-submodules https://github.com/nairyosangha/mpv-subversive.git ~/.config/mpv/scripts/mpv-subversive
```

## Usage

### Identifying media

When pressing `b` (for browse!) the plugin will ask the user to identify the media they're currently watching.

This is done by trying to parse the media's filename and extracting the title and episode number from it.

When we could not parse the filename succesfully there's a good chance no matches will be found, in this case the user is asked to provide the show name manually.
This uses the new `mp.input()` scripting functionality for which MPV version 0.38.0 is required.

### Configuration

Configuration can be done by creating a `mpv-subversive.conf` file in MPV's `script-opts` folder (`$HOME/.config/mpv/script-opts/mpv-subversive.conf` by default)

The valid settings can be viewed in [main.lua](./main.lua)

https://github.com/nairyosangha/mpv-subversive/blob/77b4a584e4c6530178879e5f2afe117a73487c8e/main.lua#L7-L25

#### Caching lookups

When looking up a new show the script will store the AniList media ID in a file called `.anilist.id` in the same directory as the file.
This file is then used for all consecutive lookups done in the same directory, so you don't have to look up each episode in a series.

This option can be disabled in the configuration, and certain directories can be excluded from being cached as well, see above.

#### Subtitle backends

##### jimaku

The script will query [jimaku.cc](https://jimaku.cc). To be able to do this, you need to [create an account](https://jimaku.cc/login) and [generate an API key](https://jimaku.cc/account).

This API key then needs to be added to the script's configuration, see above.

##### offline (WIP)

To be able to use the plugin in offline mode, you need to have a locally stored archive of subtitles, and a mapping which links an AniList ID to a path to the directory (or zip/rar file) containing subtitles for the given ID.
We look for this mapping file (with name `mapping.csv`) in the script's directory itself. This can be overwritten in the configuration.

This mapping file should have the following format:
```
<anilist_id>,/absolute/path/to/subtitle/directory
...
```
