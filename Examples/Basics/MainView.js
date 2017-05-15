var Observable = require("FuseJS/Observable");
var MediaQuery = require("FuseJS/MediaQuery");
var StreamingPlayer = require("FuseJS/StreamingPlayer");

var doonIt = false;

var foo = function() {
	var query = {
		"artist": "Alan Gogoll"
	};
	MediaQuery.tracks(query).then(function(results) {
		var tracks = results.map(function(track, index) {
			return {
				"id": index,
				"name": "jam jam jam", //track["name"],
				"artist": track["artist"],
				"url": track["path"],
				"artworkUrl":"https://everyweeks.com/pZ2j56doGB6c0ykra8lXMj7nuNTDsT79-logo.png",
				"duration": track["duration"]
			};
		});
		StreamingPlayer.setPlaylist(tracks);
	}).catch(function(e) {
		console.log("Well damn:" + e);
	});
};

module.exports = {
	foo: foo
};
