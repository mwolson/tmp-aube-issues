const path = require("path");
const Metro = require("metro");

async function main() {
    const config = await Metro.loadConfig({
        cwd: process.cwd(),
        config: path.resolve("metro.config.js"),
    });
    try {
        await Metro.buildGraph(config, {
            entries: [path.resolve("index.js")],
            minify: false,
            dev: true,
        });
        console.log("RESULT: OK");
        process.exit(0);
    } catch (error) {
        const message = String(error && error.message ? error.message : error);
        console.log("RESULT: FAIL");
        console.log(message.slice(0, 2000));
        process.exit(1);
    }
}

main().catch((error) => {
    console.log("RESULT: CRASH");
    console.error(error);
    process.exit(2);
});
