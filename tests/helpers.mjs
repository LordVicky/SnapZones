import fs from "node:fs/promises";
import vm from "node:vm";

export async function loadQmlJs(relativePath, names) {
    const source = await fs.readFile(new URL(`../${relativePath}`, import.meta.url), "utf8");
    const context = {
        console,
        Number,
        Math,
        JSON,
        Object,
        Array,
        String,
        Boolean,
        Date,
        RegExp,
        Set,
        Map,
    };
    const exportExpression = names.map(name => `${name}: typeof ${name} === "function" ? ${name} : ${name}`).join(",");
    const qmlLibraryPragma = /^\.pragma library\s*/m;
    vm.runInNewContext(`${source.replace(qmlLibraryPragma, "")}\nthis.__exports = { ${exportExpression} };`, context, { filename: relativePath });
    const exports = context.__exports;
    for (const name of names) {
        if (typeof exports[name] === "function") {
            const fn = exports[name];
            exports[name] = (...args) => {
                const value = fn(...args);
                return value && typeof value === "object" ? JSON.parse(JSON.stringify(value)) : value;
            };
        } else if (exports[name] && typeof exports[name] === "object") {
            exports[name] = JSON.parse(JSON.stringify(exports[name]));
        }
    }
    return exports;
}
