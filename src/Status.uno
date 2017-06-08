using Uno;
using Uno.UX;
using Uno.Threading;
using Fuse.Scripting;
using Uno.Collections;
using Uno.Compiler.ExportTargetInterop;

namespace StreamingPlayer
{
    public enum PlayerStatus
    {
        Stopped, Loading, Playing, Paused, Error
    }

    static class PlayerStatusConverter
    {
        public static string Stringify(this PlayerStatus status)
        {
            switch (status)
            {
                case PlayerStatus.Stopped:
                    return "Stopped";
                case PlayerStatus.Loading:
                    return "Loading";
                case PlayerStatus.Playing:
                    return "Playing";
                case PlayerStatus.Paused:
                    return "Paused";
                case PlayerStatus.Error:
                    return "Error";
                default:
                    return null;
            }
        }

        public static string Convert(Context c, PlayerStatus s)
        {
            return s.Stringify();
        }
    }

    public delegate void StatusChangedHandler(PlayerStatus status);
}
