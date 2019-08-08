require("geckodriver");

const env = require("process").env;
const fs = require("fs");
const path = require("path");
const webdriver = require("selenium-webdriver");
const Until = webdriver.until;
const By = webdriver.By;

import { extensionDir, getNewestFileMatching, sendKeys, performTest, killDriver } from "./_common"

describe("Firefox", () => {

        test("Firenvim works on txti.es", async (done) => {
                const extensionPath = await getNewestFileMatching(path.join(extensionDir, "xpi"), ".*.zip");

                // Temporary workaround until
                // https://github.com/SeleniumHQ/selenium/pull/7464 is merged
                let xpiPath
                if (extensionPath !== undefined) {
                        xpiPath = extensionPath.replace(/\.zip$/, ".xpi");
                        fs.renameSync(extensionPath, xpiPath);
                } else {
                        xpiPath = await getNewestFileMatching(path.join(extensionDir, "xpi"), ".*.xpi");
                }

                const options = (new (require("selenium-webdriver/firefox").Options)())
                        .setPreference("xpinstall.signatures.required", false)
                        .addExtensions(xpiPath);

                if (env["HEADLESS"]) {
                        options.headless()
                }

                const driver = new webdriver.Builder()
                        .forBrowser("firefox")
                        .setFirefoxOptions(options)
                        .build();
                await performTest(driver);
                await killDriver(driver);
                return done();
        })
})
