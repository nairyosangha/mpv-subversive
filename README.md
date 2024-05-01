# mpv-subversive

MPV plugin **for GNU/Linux** that makes it easy to find and load subtitles for the shows you're watching.

This plugin depends on functionality provided by the [AniList API](https://anilist.gitbook.io/anilist-apiv2-docs/overview/graphql) and [Jimaku](https://jimaku.cc/).

The code to display the GUI menu is largely borrowed from [autosubsync-mpv](https://github.com/joaquintorres/autosubsync-mpv)

## Dependencies
- unrar
- unzip
- lua5.1
- luarocks (to install luasocket and luasec)

## Installation
```sh
sudo pacman -Syu unrar unzip lua51 luarocks
sudo luarocks --lua-version 5.1 install luasocket
sudo luarocks --lua-version 5.1 install luasec
git clone --recurse-submodules https://github.com/nairyosangha/mpv-subversive.git ~/.scripts/mpv-subversive
```

## Usage

When pressing `b` (for browse!) the plugin will ask the user to identify the media they're currently watching.

This is done by trying to parse the media's filename and extracting the title and episode number from it.
Alternatively, you can create a `.anilist.id` file in the directory of the show to skip this step.
This file should contain the numeric ID used by AniList, e.g. for the [following show](https://anilist.co/anime/160090/Kaii-to-Otome-to-Kamikakushi/) the ID would be 160090.

Once we know this ID, we can use this to see if any subtitles are available for it.

### Online
When using the online mode, the plugin queries Jimaku directly. To be able to do this, you need to [create an account](https://jimaku.cc/login) and [generate an API key](https://jimaku.cc/account).
The API key then needs to be added in `main.lua`:
https://github.com/nairyosangha/mpv-subversive/blob/2325b5656fdcca0d2ed7ef546e89b5757b718ebd/main.lua#L12


### Offline (not fully done yet)
To be able to use the plugin in offline mode, you need to have a locally stored archive of subtitles, and a mapping which links AniList IDs to a absolute path to the directory containing subtitle files for this show.
By default we look for a mapping file called `mapping.csv` in the script's directory itself. This can be overwritten in `main.lua`:
https://github.com/nairyosangha/mpv-subversive/blob/2325b5656fdcca0d2ed7ef546e89b5757b718ebd/main.lua#L10

This file should have the following format:
```
<anilist_id>,/absolute/path/to/subtitle/directory
...
```
