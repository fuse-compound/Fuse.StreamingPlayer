# Expected Behavior

## Set Playlist (plus optional next-track index, optional subseq?)
- sets playlist
- if nothing is playing then current-track stays null, next-track is first in playlist
- if something is playing then current-track is untouched but next-track is first in playing
- playlists are ALWAYS fresh, app maker must maintain context in JS

## Get Playlist
- Get the current playlist & position in that playlist

## Get History
- A list of all things that have played

## Play
- plays current-track, if track playing seek to 0
- if no current-track, set next track as current & play
- if no playlist then do nothing
- is paused, resume

## Stop
- stop playing
- seek to 0
- current track stays current

## Seek
- Fine as is
- do nothing if no current track


History

Playlist

repeat/repeat-1/normal

## Android

- stop on no track crashes
-

Huh we actually have some issues:

- Previous requires history, not just playlist.
 - History requires the track objects
 - current may no longer be in the playlist
 - so getCurrent can't be an index
