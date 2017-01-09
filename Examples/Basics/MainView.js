var Observable = require("FuseJS/Observable");
var StreamingPlayer = require("FuseJS/StreamingPlayer");

var doonIt = false;

var foo = function() {
    StreamingPlayer.play({"id":0,
                         "name":"fooName",
                         "artist":"MrFoo",
                         "url":"https://ia802508.us.archive.org/5/items/testmp3testfile/mpthreetest.mp3",
                         "artworkUrl":"https://everyweeks.com/pZ2j56doGB6c0ykra8lXMj7nuNTDsT79-logo.png",
                         "duration":10});
};

module.exports = {
	foo: foo
};
