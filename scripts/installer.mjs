import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import path from 'node:path';

if (process.platform !== 'darwin') throw new Error('Build the Mac installer on macOS.');
const require = createRequire(import.meta.url);
const folder = process.arch === 'arm64' ? 'mac-arm64' : 'mac';
const app = path.resolve('release', folder, 'rAIzorMail.app');
// Package the already signed app so the disk image preserves its signature.
execFileSync('codesign', ['--verify', '--deep', '--strict', app], { stdio: 'inherit' });
execFileSync(process.execPath, [require.resolve('electron-builder/cli.js'), '--mac', 'dmg', `--${process.arch}`, '--prepackaged', app], { stdio: 'inherit' });
