# mpv-subversive

MPV (v0.38.0+) plugin **for GNU/Linux** that makes it easy to find and load subtitles for the shows you're watching.

https://github.com/nairyosangha/mpv-subversive/assets/34285115/dc5cf7ab-9d19-4dce-952d-af80fe563ca2



This plugin depends on functionality provided by the [AniList API](https://anilist.gitbook.io/anilist-apiv2-docs/overview/graphql) and [Jimaku](https://jimaku.cc/).

The code to display the GUI menu is largely borrowed from [autosubsync-mpv](https://github.com/joaquintorres/autosubsync-mpv)

## Dependencies
- unrar
- unzip
- 7zip
- lua5.1
- luarocks (to install luasocket and luasec)

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

Alternatively, you can create a `.anilist.id` file in the directory of the show to skip this step.
This file should contain the numeric ID used by AniList, e.g. for the [following show](https://anilist.co/anime/160090/Kaii-to-Otome-to-Kamikakushi/) the ID would be 160090.

Once we know this ID, we can use this to see if any subtitles are available for it.

### Finding suitable subtitles

#### Online (Jimaku)

When using the online mode, the plugin queries Jimaku directly. To be able to do this, you need to [create an account](https://jimaku.cc/login) and [generate an API key](https://jimaku.cc/account).
The API key then needs to be added in `main.lua`:
https://github.com/nairyosangha/mpv-subversive/blob/2325b5656fdcca0d2ed7ef546e89b5757b718ebd/main.lua#L12


#### Offline (local mapping file)
To be able to use the plugin in offline mode, you need to have a locally stored archive of subtitles, and a mapping which links an AniList ID to a path to the directory (or zip/rar file) containing subtitles for the given ID.
By default we look for a mapping file called `mapping.csv` in the script's directory itself. This can be overwritten in `main.lua`:
https://github.com/nairyosangha/mpv-subversive/blob/2325b5656fdcca0d2ed7ef546e89b5757b718ebd/main.lua#L10

This file should have the following format:
```
<anilist_id>,/absolute/path/to/subtitle/directory
...
```
