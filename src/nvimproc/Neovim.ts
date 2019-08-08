// lgtm[js/unused-local-variable]
import * as browser from "webextension-polyfill";
import { page } from "../page/proxy";
import { onRedraw } from "../render/Redraw";
import { Stdin } from "./Stdin";
import { Stdout } from "./Stdout";

export async function neovim(
        element: HTMLPreElement,
        selector: string,
        { port, password }: { port: number, password: number },
    ) {
    let stdin: Stdin;
    let stdout: Stdout;
    let reqId = 0;
    const requests = new Map<number, { resolve: any, reject: any }>();

    document.body.appendChild(document.createTextNode(`Creating websocket ${port}/${password}`));
    const socket = new WebSocket(`ws://127.0.0.1:${port}/${password}`);
    document.body.appendChild(document.createTextNode("WebSocket created."));
    document.addEventListener("error", (err) => {
        document.body.appendChild(document.createTextNode(err.toString()));
    });
    document.addEventListener("beforeunload", () => {
        document.body.appendChild(document.createTextNode("beforeunload"));
        socket.close()
    });
    socket.binaryType = "arraybuffer";
    socket.addEventListener("close", ((_: any) => {
        document.body.appendChild(document.createTextNode("socket closed"));
        console.log(`Port disconnected for element ${selector}.`);
        // - page.killEditor(selector);
    }));
    document.body.appendChild(document.createTextNode("listeners created"));
    await (new Promise(resolve => socket.addEventListener("open", () => {
        document.body.appendChild(document.createTextNode("socket open"));
        resolve();
    })));
    document.body.appendChild(document.createTextNode("socket opened"));
    stdin = new Stdin(socket);
    stdout = new Stdout(socket);

    const request = (api: string, args: any[]) => {
        return new Promise((resolve, reject) => {
            reqId += 1;
            const r = requests.get(reqId);
            if (r) {
                console.error(`reqId ${reqId} already taken!`);
            }
            requests.set(reqId, {resolve, reject});
            stdin.write(reqId, api, args);
        });
    };
    stdout.addListener("request", (id: any, name: any, args: any) => {
        console.log("received request", id, name, args);
    });
    stdout.addListener("response", (id: any, error: any, result: any) => {
        const r = requests.get(id);
        if (!r) {
            // This can't happen and yet it sometimes does, possibly due to a firefox bug
            console.error(`Received answer to ${id} but no handler found!`);
        } else {
            requests.delete(id);
            if (error) {
                r.reject(error);
            } else {
                r.resolve(result);
            }
        }
    });
    stdout.addListener("notification", async (name: string, args: any[]) => {
        switch (name) {
            case "redraw":
                onRedraw(args, element, selector);
                break;
            case "firenvim_bufwrite":
                page.setElementContent(selector, args[0].text.join("\n"));
                break;
            case "firenvim_vimleave":
                page.killEditor(selector);
                break;
            default:
                console.log(`Unhandled notification '${name}':`, args);
                break;
        }
    });

    document.body.appendChild(document.createTextNode("before nvim_get_api_info"));
    const { 1: apiInfo } = (await request("nvim_get_api_info", [])) as INvimApiInfo;
    return apiInfo.functions
        .filter(f => f.deprecated_since === undefined)
        .reduce((acc, cur) => {
            let name = cur.name;
            if (name.startsWith("nvim_")) {
                name = name.slice(5);
            }
            acc[name] = (...args: any[]) => request(cur.name, args);
            return acc;
        }, {} as {[k: string]: (...args: any[]) => any});
}
