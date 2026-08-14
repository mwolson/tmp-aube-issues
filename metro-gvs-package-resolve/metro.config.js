const path = require("path");
const { getDefaultConfig, mergeConfig } = require("metro-config");

const projectRoot = __dirname;
const extraWatch = (process.env.METRO_WATCH_FOLDERS || "")
    .split(path.delimiter)
    .map((item) => item.trim())
    .filter(Boolean);
const extraNodeModules = {};
if (process.env.METRO_EXTRA_NODE_MODULES) {
    for (const entry of process.env.METRO_EXTRA_NODE_MODULES.split(",")) {
        const splitAt = entry.indexOf("=");
        if (splitAt <= 0) {
            continue;
        }
        extraNodeModules[entry.slice(0, splitAt)] = entry.slice(splitAt + 1);
    }
}

module.exports = (async () => {
    const defaultConfig = await getDefaultConfig(projectRoot);
    return mergeConfig(defaultConfig, {
        projectRoot,
        watchFolders: [projectRoot, ...extraWatch],
        fileMapCacheDirectory: path.join(projectRoot, ".metro-cache"),
        resolver: {
            sourceExts: ["js", "json"],
            extraNodeModules,
        },
        transformer: {
            getTransformOptions: async () => ({
                transform: {
                    experimentalImportSupport: false,
                    inlineRequires: false,
                },
            }),
        },
    });
})();
