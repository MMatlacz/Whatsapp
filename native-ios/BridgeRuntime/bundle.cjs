const fs = require('node:fs');
const path = require('node:path');
const root = __dirname;
const dependency = path.join(root, 'node_modules/@wppconnect/wa-js');
const metadata = JSON.parse(fs.readFileSync(path.join(dependency, 'package.json'), 'utf8'));
if (metadata.version !== '4.6.0' || metadata.license !== 'Apache-2.0') {
    throw new Error('Unexpected runtime dependency; review version and licensing before bundling.');
}
const output = path.join(root, 'generated');
fs.mkdirSync(output, { recursive: true });
// Preserve the complete supplied license and bundled third-party notices alongside the script.
for (const [source, destination] of [
    ['LICENSE', 'WAJS-LICENSE.txt'],
    ['dist/wppconnect-wa.js.LICENSE.txt', 'wppconnect-wa.js.LICENSE.txt']
]) fs.copyFileSync(path.join(dependency, source), path.join(output, destination));
const script = fs.readFileSync(path.join(dependency, 'dist/wppconnect-wa.js'), 'utf8')
    + '\n;\n' + fs.readFileSync(path.join(root, 'adapter.js'), 'utf8');
fs.writeFileSync(path.join(output, 'WhatsAppRuntime.js'), script);
console.log(`Bundled WA-JS ${metadata.version}; ${Buffer.byteLength(script)} bytes. No network runtime dependency.`);
