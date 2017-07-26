using Fuse;
using Uno;
using Uno.UX;
using Fuse.Scripting;
using Uno.Collections;
using Uno.Compiler.ExportTargetInterop;

namespace StreamingPlayer
{

    public class Track
    {
        static int _lastUID = 0;

        public readonly int UID;
        public readonly string Name;
        public readonly string Artist;
        public readonly string Url;
        public readonly string ArtworkUrl;
        public readonly double Duration;

        public Track(int uid, string name, string artist, string url, string artworkUrl, double duration)
        {
            UID = uid;
            Name = name;
            Artist = artist;
            Url = url;
            ArtworkUrl = artworkUrl;
            Duration = duration;
        }

        public override bool Equals(object obj)
        {
            var t = obj as Track;
            return (t != null
                    && t.UID == UID
                    && t.Name == Name
                    && t.Artist == Artist
                    && t.Url == Url);
        }

        public override string ToString()
        {
            return "Track:" +
                ": UID: " + UID +
                ": Name: " + Name +
                ", Artist: " + Artist +
                ", Url: " + Url +
                ", ArtworkUrl: " + ArtworkUrl +
                ", Duration: " + Duration;
        }

        public static Fuse.Scripting.Object ToJSObject(Context c, Track t)
        {
            if (t == null)
                return null;
            var obj = c.NewObject();
            obj["uid"] = t.UID;
            obj["name"] = t.Name;
            obj["artist"] = t.Artist;
            obj["url"] = t.Url;
            obj["artworkUrl"] = t.ArtworkUrl;
            obj["duration"] = t.Duration;
            return obj;
        }

        internal static int NewUID()
        {
            return _lastUID+=1;
        }
    }

    class TrackConverter : Marshal.IConverter
    {
        public bool CanConvert(Type t)
        {
            return t == typeof(Track);
        }

        public object TryConvert(Type t, object o)
        {
            if (CanConvert(t))
            {
                var jsObject = (Fuse.Scripting.Object)o;
                var uid = Marshal.ToInt(jsObject["uid"]);
                var name = jsObject["name"].ToString();
                var artist = jsObject["artist"].ToString();
                var url = jsObject["url"].ToString();
                var artworkUrl = jsObject["artworkUrl"].ToString();
                var duration = Marshal.ToDouble(jsObject["duration"]);
                return new Track(uid, name, artist, url, artworkUrl, duration);
            }
            return null;
        }
    }
}
