import * as msgpack from "msgpack-lite";
// lgtm[js/unused-local-variable]
import * as browser from "webextension-polyfill";

export class Stdin {

    constructor(private socket: WebSocket) {}

    public write(reqId: number, method: string, args: any[]) {
        const req = [0, reqId, method, args];
        document.body.appendChild(document.createTextNode(req.toString()));
        const encoded = msgpack.encode(req);
        this.socket.send(encoded);
    }

}
