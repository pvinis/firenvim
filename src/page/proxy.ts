import * as browser from "webextension-polyfill";
import { getFunctions } from "./functions";

// We don't need to give real values to getFunctions since we're only trying to
// get the name of functions that exist in the page.
const functions = getFunctions({} as any);

type ft = typeof functions;
type ArgumentsType<T> = T extends  (...args: infer U) => any ? U: never;

export const page = {} as { [k in keyof ft]: (...args: ArgumentsType<ft[k]>) => Promise<ReturnType<ft[k]>> };

let funcName: keyof typeof functions;
for (funcName in functions) {
    if (!functions.hasOwnProperty(funcName)) { // Make tslint happy
        continue;
    }
    // We need to declare func here because funcName is a global and would not
    // be captured in the closure otherwise
    const func = funcName;
    page[func] = ((...arr: any[]) => {
        return browser.runtime.sendMessage({
            args: {
                args: arr,
                funcName: [func],
            },
            funcName: ["messageOwnTab"],
        });
    });
}
