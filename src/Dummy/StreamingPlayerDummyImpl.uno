using Uno;
using Uno.UX;
using Uno.Threading;
using Fuse;
using Fuse.Scripting;
using Uno.Collections;
using Uno.Compiler.ExportTargetInterop;

namespace StreamingPlayer
{
    extern(!Android && !iOS) static class StreamingPlayer
    {
        static public PlayerStatus Status = PlayerStatus.Stopped;
        static public double Duration = 200.0;
        static public double Progress = 0.0;
        static public Track CurrentTrack = null;
        static public bool HasPrevious = false;
        static public bool HasNext = false;

        static public event StatusChangedHandler StatusChanged;
        static public event Action CurrentTrackChanged;

        static public bool Init() { return true; }
        static public void SetPlaylist(Track[] tracks) {}
        static public void Play(Track track) {}
        static public void Resume() {}
        static public void Pause() {}
        static public void Stop() {}
        static public void Seek(double toProgress) {}
        static public int Previous() { return 0; }
        static public int Next() { return 0; }
    }
}
