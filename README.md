# WARNING WIP

I'm still actively working on this, there are bugs on both targets. I need to take a quick detour to make a media query library before I can come back and finish this.

# Fuse.StreamingPlayer

This is a player that can work on both http & local audio files. It's intended purpose is for playback of music.

It supports:
- playback even when the app is in the background
- Lock screen controls
    - Normal lock screen controls on iOS
    - MediaStyle notification for Android
    - Displays media metadata
        - Track title
        - Artist
        - Artwork
        - Duration
        - Progress
- Allows you to supply a full playlist of tracks from JS

## JS API
It exposes a JavaScript API called `PlaylistPlayer` which is reachable by `require('PlaylistPlayer')`. I'll fill this section in when I've finished this (see the big ol' warning at the top :p) You can also look at the [example](./Examples/Basics/MainView.js) to see where we are going with this.

## Limitations

- Only supports Android API level >= 21. Earlier API levels used a different system for lock screen media controls, which have not been wrapped yet.
- A few notification related callbacks have not yet been wrapped (like the clicked and removed actions).
