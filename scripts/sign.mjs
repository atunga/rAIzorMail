import { execFileSync } from 'node:child_process';
import path from 'node:path';
if (process.platform !== 'darwin') throw new Error('Build the Mac app on macOS.');
const folder = process.arch === 'arm64' ? 'mac-arm64' : 'mac';
const app = path.resolve('release', folder, 'rAIzorMail.app');
execFileSync('codesign', ['--force', '--deep', '--sign', '-', app], { stdio: 'inherit' });
execFileSync('codesign', ['--verify', '--deep', '--strict', app], { stdio: 'inherit' });
console.log(`Ready: ${app}`);
