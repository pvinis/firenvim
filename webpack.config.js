const CopyWebPackPlugin = require("copy-webpack-plugin");

function deepCopy (obj) {
  if (obj instanceof Array) {
    return obj.slice();
  }
  const result = {};
  Object.assign(result, obj);
  Object.keys(result)
    .filter(key => (typeof result[key]) === "object")
    .forEach(key => result[key] = deepCopy(result[key]));
  return result;
};

const CopyWebPackFiles = [
  "src/manifest.json",
  "src/NeovimFrame.html",
  "src/preferences/preferences.html",
  "static/firenvim.svg",
]

const config = {
  mode: "development",

  entry: {
    background: "./src/background.ts",
    content: "./src/content.ts",
    preferences: "./src/preferences/preferences.ts",
    nvimui: "./src/NeovimFrame.ts",
  },
  output: {
    filename: "[name].js",
    // Overwritten by browser-specific config
    // path: __dirname + "/target/extension",
  },

  // Enable sourcemaps for debugging webpack's output.
  devtool: "inline-source-map",

  resolve: {
    // Add '.ts' and '.tsx' as resolvable extensions.
    extensions: [".ts", ".tsx", ".js", ".json"],
  },

  module: {
    rules: [
      // All files with a '.ts' or '.tsx' extension will be handled by 'awesome-typescript-loader'.
      { test: /\.tsx?$/, loader: "awesome-typescript-loader" },
    ],
  },

  // Overwritten by browser-specific config
  plugins: [],
}

const path = require("path")
const version = JSON.parse(require("fs").readFileSync(path.join(__dirname, "package.json"))).version;

module.exports = [
  Object.assign(deepCopy(config), {
    output: {
      path: __dirname + "/target/chrome",
    },
    plugins: [new CopyWebPackPlugin(CopyWebPackFiles.map(file => ({
      from: file,
      to: __dirname + "/target/chrome",
      transform: (content, src) => {
        switch(path.basename(src)) {
          case "manifest.json":
            return content.toString().replace("BROWSER_SPECIFIC_SETTINGS,", ``)
              .replace("FIRENVIM_VERSION", version);
            break;
        }
        return content;
      }
    })))]
  }),
  Object.assign(deepCopy(config), {
    output: {
      path: __dirname + "/target/firefox",
    },
    plugins: [new CopyWebPackPlugin(CopyWebPackFiles.map(file => ({
      from: file,
      to: __dirname + "/target/firefox",
      transform: (content, src) => {
        switch(path.basename(src)) {
          case "manifest.json":
            return content.toString().replace("BROWSER_SPECIFIC_SETTINGS,", `
  "browser_specific_settings": {
    "gecko": {
      "id": "firenvim@lacamb.re",
      "strict_min_version": "65.0"
    }
  },`)
              .replace("FIRENVIM_VERSION", version);
            break;
        }
        return content;
      }
    })))]
  }),
];
