class RemoteAPIClient {
    constructor(host = 'localhost', port = 23050, codec = "cbor") {
        this.host = host;
        this.port = port;
        this.codec = codec;
        this.websocket = new WebSocket(`ws://${this.host}:${this.port}`);
        var client = this;
        if(this.codec == 'cbor') {
            this.websocket.binaryType = "arraybuffer";
            this.websocket.request = function(data, replyHandler) {
                var oldHandler = client.websocket.onmessage;
                client.websocket.onmessage = function(event) {
                    client.websocket.onmessage = oldHandler;
                    replyHandler(CBOR.decode(event.data));
                }
                client.websocket.send(CBOR.encode(data))
            }
        } else if(this.codec == "json") {
            this.websocket.request = function(data, replyHandler) {
                var oldHandler = client.websocket.onmessage;
                client.websocket.onmessage = function(event) {
                    client.websocket.onmessage = oldHandler;
                    replyHandler(JSON.parse(event.data));
                }
                client.websocket.send(JSON.stringify(data))
            }
        }
    }

    call(func, args, resultHandler, errorHandler = null) {
        this.websocket.request({func, args}, function(reply) {
            if(reply.success) {
                resultHandler(...reply.ret);
            } else {
                console.log(`call to "${func}" failed: ${reply.error}`);
                if(errorHandler !== null)
                    errorHandler(reply.error);
            }
        });
    }

    getObject(name, resultHandler, errorHandler = null, _info = null) {
        var client = this;
        if(_info === null) {
            this.call('wsRemoteApi.info', [name], function(r) {
                resultHandler(client.getObject(name, null, null, r));
            });
        } else {
            var ret = {}
            for(let k in _info) {
                var v = _info[k];
                if(Object.keys(v).length == 1 && v['func'] !== undefined)
                    ret[k] = function(args, resultHandler, errorHandler = null) {
                        client.call(name + "." + k, args, resultHandler, errorHandler);
                    };
                else if(Object.keys(v).length == 1 && v['const'] !== undefined)
                    ret[k] = v['const'];
                else
                    ret[k] = this.getObject(name + "." + k, null, null, v);
            }
            return ret
        }
    }
}
