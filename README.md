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

This file should look like this, 2 columns are expected, the anilist ID and a relative path to the local mapping directory.
```
3269,"./mapping/.hack//G.U. Trilogy"
11755,"./mapping/009 RE:CYBORG"
5525,"./mapping/07-Ghost"
116242,"./mapping/100-man no Inochi no Ue ni Ore wa Tatteiru"
127366,"./mapping/100-man no Inochi no Ue ni Ore wa Tatteiru 2nd Season"
6682,"./mapping/11eyes"
159559,"./mapping/16bit Sensation: ANOTHER LAYER"
133411,"./mapping/180-byou de Kimi no Mimi wo Shiawase ni Dekiru ka?"
161680,"./mapping/1LDK+JK Ikinari Doukyo? Micchaku!? Hatsu Ecchi!!?"
113231,"./mapping/2.43: Seiin Koukou Danshi Volley-bu"
```

A script to create this mapping is provided: `build_offline_mapping.lua`. To run this script you'll need the following:

- https://github.com/rxi/json.lua -> download the json.lua file and save it in this directory

- fill in your API key here: https://github.com/nairyosangha/mpv-subversive/blob/ad2fb7233ac3f6604b2c2b0214b7072de6cb1844/build_offline_archive.lua#L7
- https://github.com/luaposix/luaposix (optional) -> can also be installed with luarocks, see instructions above

If you don't want to install luaposix, you should uncomment the line that saves the mapping every so often. If you don't, it will only attempt to save the mapping at the very end, so if something goes wrong during the initial load you'll have to try all over again.

https://github.com/nairyosangha/mpv-subversive/blob/ad2fb7233ac3f6604b2c2b0214b7072de6cb1844/build_offline_archive.lua#L75-L76

To run the script, you can simply do `luajit ./build_offline_mapping.lua`

Luajit is a dependency of MPV so it should be preinstalled. It will probably work with Lua 5.1 as well.
