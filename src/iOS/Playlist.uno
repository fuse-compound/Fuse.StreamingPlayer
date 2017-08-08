using Uno;
using Uno.UX;
using Uno.Threading;
using Fuse.Scripting;
using Uno.Collections;
using Uno.Compiler.ExportTargetInterop;

namespace StreamingPlayer
{
    internal static class Playlist
    {
        // Playlist, History & Current

        static Dictionary<int, Track> _tracks = new Dictionary<int, Track>();
        static List<int> _trackPlaylist = new List<int>();
        static List<int> _trackHistory = new List<int>();
        static int _trackPlaylistCurrentIndex = -1;
        static int _trackHistoryCurrentIndex = -1;

        public static void SetPlaylistCurrent(int uid)
        {
            _trackPlaylistCurrentIndex = _trackPlaylist.IndexOf(uid);
        }

        public static Track TrackForID(int uid)
        {
            return _tracks[uid];
        }

        public static int PlaylistNextTrackUID()
        {
            int i = _trackPlaylistCurrentIndex + 1;
            if (i >= _trackPlaylist.Count)
            {
                return -1;
            }
            return _trackPlaylist[i];
        }

        public static int PlaylistPrevTrackUID()
        {
            int i = _trackPlaylistCurrentIndex - 1;
            if (i < 0)
            {
                return -1;
            }
            return _trackPlaylist[i];
        }

        static int HistoryAt(int index)
        {
            return _trackHistory[_trackHistory.Count - (1 + index)];
        }

        static int HistoryNextTrackUID()
        {
            int i = _trackHistoryCurrentIndex - 1;
            if (i < 0)
            {
                return -1;
            }
            return HistoryAt(i);
        }

        static int HistoryPrevTrackUID()
        {
            int i = _trackHistoryCurrentIndex + 1;
            if (i >= _trackHistory.Count)
            {
                return -1;
            }
            return HistoryAt(i);
        }

        // Modify Playlist and History

        static void PushCurrentToHistory()
        {
            int cur = _trackPlaylistCurrentIndex;
            if (cur >= 0)
            {
                _trackHistory.Add(_trackPlaylist[cur]);
            }
        }

        static void DropFuture()
        {
            if (_trackHistoryCurrentIndex>-1)
            {
                var at = _trackHistory.Count - _trackHistoryCurrentIndex;
                for (int i = 0; i < _trackHistoryCurrentIndex; i++)
                {
                    _trackHistory.RemoveAt(at);
                }
                _trackHistoryCurrentIndex = -1;
            }
        }

        public static int MoveToNextPlaylistTrack()
        {
            int uid = PlaylistNextTrackUID();
            if (uid >=0)
            {
                // If we were playing from history then we dont want to push the current
                // track to history as it is already there.
                bool wasntPlayingFromHistory = _trackHistoryCurrentIndex == -1;

                // If we were in the history then moving structurally starts making a new
                // history. This means we drop the future.
                DropFuture();

                if (wasntPlayingFromHistory)
                {
                    PushCurrentToHistory();
                }

                _trackPlaylistCurrentIndex += 1;
            }
            return uid;
        }

        public static int MoveToPrevPlaylistTrack()
        {
            int uid = PlaylistPrevTrackUID();
            if (uid >=0)
            {
                // If we were playing from history then we dont want to push the current
                // track to history as it is already there.
                bool wasntPlayingFromHistory = _trackHistoryCurrentIndex == -1;

                // If we were in the history then moving structurally starts making a new
                // history. This means we drop the future.
                DropFuture();

                if (wasntPlayingFromHistory)
                {
                    PushCurrentToHistory();
                }

                _trackPlaylistCurrentIndex -= 1;
            }
            return uid;
        }

        public static int MoveBackInHistory()
        {
            int uid = HistoryPrevTrackUID();
            if (uid >=0)
            {
                _trackHistoryCurrentIndex += 1;
                int playlistIndex = _trackPlaylist.IndexOf(uid); // -1 if not found
                if (playlistIndex >= 0)
                {
                    _trackPlaylistCurrentIndex = playlistIndex;
                }
            }
            return uid;
        }

        public static int MoveForwardInHistory()
        {
            int uid = HistoryNextTrackUID();
            if (uid >=0)
            {
                _trackHistoryCurrentIndex -= 1;
                int playlistIndex = _trackPlaylist.IndexOf(uid); // -1 if not found
                if (playlistIndex >= 0)
                {
                    _trackPlaylistCurrentIndex = playlistIndex;
                }
                return uid;
            }
            else
            {
                return MoveToNextPlaylistTrack();
            }
        }

        static void ClearHistory()
        {
            // neccesary when people want to set the playlist and not let it be possible
            // to go back in history to tracks not in the playlist.
            _trackHistory.Clear();
            _trackHistoryCurrentIndex = -1;

            // We no longer need any tracks that arent in the playlist as there is no way
            // to navigate to them
            List<Track> keep = new List<Track>();

            foreach (int uid in _trackPlaylist)
                keep.Add(_tracks[uid]);

            _tracks.Clear();

            foreach (Track track in keep)
                _tracks.Add(track.UID, track);
        }

        public static void SetPlaylist(List<Track> tracks, int currentTrackUID)
        {
            _trackPlaylist.Clear();

            foreach (Track track in tracks)
            {
                _tracks.Add(track.UID, track);
                _trackPlaylist.Add(track.UID);
            }

            SetPlaylistCurrent(currentTrackUID);
        }

        public static int SetCurrentPlaylistTrack(int trackUID)
        {

            int index = _trackPlaylist.IndexOf(trackUID);
            if (index > -1)
            {
                // If we were playing from history then we dont want to push the current
                // track to history as it is already there.
                bool wasntPlayingFromHistory = _trackHistoryCurrentIndex == -1;

                // If we were in the history then moving structurally starts making a new
                // history. This means we drop the future.
                DropFuture();

                if (wasntPlayingFromHistory)
                {
                    PushCurrentToHistory();
                }

                _trackPlaylistCurrentIndex = index;
                return trackUID;
            }
            else
            {
                return -1;
            }
        }
    }
}
