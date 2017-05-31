package com.fuse.StreamingPlayer;

public enum AndroidPlayerState
{
    Idle, //0
    Initialized, //1
    Preparing, //2
    Prepared, //3
    Started, //4
    Stopped, //5
    Paused, //6
    PlaybackCompleted, //7
    Error, //8
    End; //9

    public int toInt()
    {
        switch (this)
        {
            case Idle:
                return 0;
            case Initialized:
                return 1;
            case Preparing:
                return 2;
            case Prepared:
                return 3;
            case Started:
                return 4;
            case Stopped:
                return 5;
            case Paused:
                return 6;
            case PlaybackCompleted:
                return 7;
            case Error:
                return 8;
            case End:
                return 9;
            default:
                return 0;
        }
    }
}
