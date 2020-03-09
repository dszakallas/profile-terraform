'use strict';
var trailing_slash_re = /\/$/;
exports.handler = (event, context, callback) => {
    var request = event.Records[0].cf.request;
    var olduri = request.uri;
    var newuri = olduri.replace(trailing_slash_re, '\/index.html');
    request.uri = newuri;
    return callback(null, request);
};

