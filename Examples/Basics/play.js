var Observable = require("FuseJS/Observable");
var MediaQuery = require("FuseJS/MediaQuery");
var StreamingPlayer = require("FuseJS/StreamingPlayer");

var tracks = Observable();

var paramObs = this.Parameter.onValueChanged(module, function(param) {
	MediaQuery.tracks({ "artist": param["artistID"] }).then(function(tracksArray) {
		var tmp = tracksArray.map(function(track, index) {
			return {
				"id": index,
				"name": track["title"],
				"artist": track["artist"],
				"url": track["path"],
				"artworkUrl":"https://everyweeks.com/pZ2j56doGB6c0ykra8lXMj7nuNTDsT79-logo.png",
				"duration": track["duration"]
			};
		});
		StreamingPlayer.playlist = tmp;
		tracks.addAll(StreamingPlayer.playlist);
	}).catch(function(e) {
		console.log("Well damn:" + e);
	});
});

var itemClicked = function(item) {
	var track = item["data"];
	console.log("Foo?: " + JSON.stringify(track));
	StreamingPlayer.switchTrack(track);
};

var backClicked = function() {
	StreamingPlayer.stop();
	StreamingPlayer.removeAllListeners();
	router.goto("artists");
};

StreamingPlayer.on("currentTrackChanged", function(track) {
	console.log("Track Changed: " + JSON.stringify(track));
});

StreamingPlayer.on("statusChanged", function(status) {
	console.log("Status Changed: " + JSON.stringify(status));
});

module.exports = {
	prevClicked: StreamingPlayer.previous,
	nextClicked: StreamingPlayer.next,
	backwardClicked: StreamingPlayer.backward,
	forwardClicked: StreamingPlayer.forward,

	backClicked: backClicked,
	playClicked: StreamingPlayer.play,
	pauseClicked: StreamingPlayer.pause,
	itemClicked: itemClicked,

	tracks: tracks
};
