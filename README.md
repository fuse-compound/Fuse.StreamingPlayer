# Fuse.StreamingPlayer

This is a simple music player for iOS & Android. It supports local & remotes files and lockscreen controls for both platforms.

The player runs in a service meaning that it keeps working when your app is in the background.

There are three main concepts to remember when using this library: Tracks, The Playlist & History.

## Tracks

Tracks are simple JS objects that have at least the following:

```
{
    "url": "...",       // http or https url OR path to local file
    "duration": 140.0   // duration of track in seconds
}
```

You may optionally provide more info:

```
{
    "url": "..."
    "duration": 140.0
    "name": "someTrackName",   // name of track
    "artist": "someArtistName" // name of artist
    "artworkUrl": "..."        // http or https url OR path to local file
}
```
This is optional but is used for the system's audio or lockscreen controls.

*TIP:* If you are not sure how to get this info for local file one option is [Fuse.MediaQuery](https://github.com/fuse-compound/Fuse.MediaQuery). The example in `Examples/Basics/` shows `Fuse.StreamingPlayer` being used in combination with `Fuse.MediaQuery`

## The Playlist

`Fuse.StreamingPlayer` has a playlist which is a simple JS array or `Track`s. You can set it like this

```
var Player = require("FuseJS/StreamingPlayer");
Player.playlist = [{ "url": "a.mp3", "duration": 140.0, .. }, { "url": "b.mp3", "duration": 200.0, .. }];
```

When you do this a *very* important transformation is done to the tracks, each one is given a unique identifier. The unique identifier (UID) is a number that will be stored in the `uid` property on the track. So, for example, the playlist in the example above will now contain tracks like this:

```
[
    { "_uid": 22, "url": "a.mp3", "duration": 140.0, .. },
    { "_uid": 30, "url": "b.mp3", "duration": 200.0, .. }
]
```

The UIDs *may* be sequential but *do not* rely on this! The reason for the UID is that, when you modify the playlist it allows the player to easily see what has changed. It can then send this info the background service that is doing the actual playback. This is why this library doesnt need to have `appendTrack`, `prependTrack`, `insertTrack`, etc. You simple make a regular old javascript array and set `Player.playlist` to that array.

## History

There are two ways to navigate through your tracks. Through the playlist & through history.

When you use `next()` & `previous()` you will move forward and backwards through your playlist. In fancy terms we are moving structurally.

When you use `forward()` & `backward()` you will move through the playback history. In fancy terms again, we are moving temporally.

Lets imagine we have a playlist of tracks `a.mp3`, `b.mp3`, `c.mp3` & `d.mp3` in that order:

First you play `c.mp3`, then `d.mp3`, then `b.mp3`

If you called `previous()` at this point it will play `a.mp3`, as `a.mp3` is the next track before `b.mp3`in the playlist.

If you called `backward()` at this point it will play `d.mp3`, as `d.mp3` is the next track you played before playing `b.mp3`

There is no *correct* choice for how your music player should behave so we provide both.

An interesting behavior is that, by default, you can play tracks that are no longer in your current playlist using `backward()`. If you dont want this behaviour then be sure to call `clearHistory()` before setting your new playlist.

## API

Finally here are the functions, properties and events provided by `Fuse.StreamingPlayer`:

- WIP -

### next()

Play the next track in the playlist -or- if nothing is play, start playing the first track in the playlist

### previous()

Play the previous track in the playlist

### backward()

Play the previous track in the play history or do nothing if there is nothing in the history

### forward()

If you have used `backward()` to move back in history then `forward()` moves you forward in history. If you are not playing from history this behaves the same as `next()`

### play()

If playback is paused, resume the playback.

If there is no currently playing track play the first track in the playlist (effectively calling `next()`)

### pause()

Pause the currently playing track

### stop()

Stop playback, setting current track to null.

### seek(seconds)

Seek to a particular point in the track

### switchTrack(track_object)

Focus a particular track from the playlist

### clearHistory()

Clear the list of previously played tracks

### status

A property which returns the current state of the player. Generally it is preferred to use the `statusChanged` event so you are informed of all changes

### currentTrack

A property which returns the currently playing track object

### duration

A property which returns the duration of the currently playing track. This is identical to `Player.currentTrack.duration`

### progress

A property which returns the current playback position (in seconds) in the track

### playlist

Returns the current playlist as an array of track objects

## statusChanged

An event which fires when the status of the player has changed. The value passed to the callback function will be on the following strings:

- "Stopped"
- "Loading"
- "Playing"
- "Paused"
- "Error"

## currentTrackChanged

An event which fires when the currently playing track has changed. Currently this does not pass the track object to the callback function so please use the `currentTrack` property
