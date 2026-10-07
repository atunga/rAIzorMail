import { app, BrowserWindow, Menu, ipcMain, dialog, shell, session, nativeImage, screen } from 'electron';
import path from 'node:path';
import fs from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { SecureStore } from './store.mjs';
import { GoogleService } from './google.mjs';
import { connectGoogle } from './oauth.mjs';
import { messageBounds } from './window-position.mjs';
const directory = path.dirname(fileURLToPath(import.meta.url));
const indexFile = path.join(directory, '../dist/index.html');
const windowKeys = new Map(); let mainWindow, store, service, signingIn = false;
const closeGuards = new Set(); let exitRequest = null, allowQuit = false;
function requestExit(window, kind) {
  if (exitRequest) return;
  exitRequest = { windowId: window.id, kind }; window.show(); window.focus(); window.webContents.send('mail:requestClose');
}
function continueQuit() {
  const guarded = BrowserWindow.getAllWindows().find(w => closeGuards.has(w.id));
  if (guarded) requestExit(guarded, 'quit');
  else { allowQuit = true; app.quit(); }
}
app.on('before-quit', event => {
  if (!allowQuit && closeGuards.size) { event.preventDefault(); continueQuit(); }
});
app.setName('rAIzorMail');
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) app.quit();
else {
  app.on('second-instance', () => { if (mainWindow) { if (mainWindow.isMinimized()) mainWindow.restore(); mainWindow.show(); mainWindow.focus(); } });
  app.whenReady().then(start).catch(error => { dialog.showErrorBox('rAIzorMail could not start', error.message); app.quit(); });
}
function broadcast(change) { for (const w of BrowserWindow.getAllWindows()) w.webContents.send('mail:changed', change); }
function command(name) { (BrowserWindow.getFocusedWindow() || mainWindow)?.webContents.send('mail:command', name); }
function trusted(event) { const url = event.senderFrame?.url; return event.senderFrame === event.sender.mainFrame && url && url.split('?')[0].split('#')[0] === pathToFileURL(indexFile).href; }
function placeMessage(window, owner) {
  if (!owner || owner.isDestroyed()) return;
  const bounds = owner.getBounds();
  const area = screen.getDisplayMatching(bounds).workArea;
  window.setBounds(messageBounds(bounds, area, window.getBounds()));
}
async function createWindow(query = {}, owner) {
  const isMessage = !!query.message;
  const w = new BrowserWindow({ width: isMessage ? 900 : 1510, height: isMessage ? 800 : 960, minWidth: isMessage ? 620 : 1000, minHeight: 620, title: 'rAIzorMail', titleBarStyle: 'hiddenInset', trafficLightPosition: { x: 20, y: 21 }, backgroundColor: '#20211e', show: false, webPreferences: { preload: path.join(directory, 'preload.cjs'), contextIsolation: true, nodeIntegration: false, sandbox: true, webSecurity: true } });
  w.on('close', event => { if (!allowQuit && closeGuards.has(w.id)) { event.preventDefault(); requestExit(w, 'window'); } });
  w.on('closed', () => { closeGuards.delete(w.id); if (exitRequest?.windowId === w.id) exitRequest = null; });
  // Independent windows can move between monitors without being attached to the main window.
  w.webContents.setWindowOpenHandler(({ url }) => { openSafeExternal(url); return { action: 'deny' }; });
  w.webContents.on('will-navigate', (event, url) => { if (url.split('?')[0] !== pathToFileURL(indexFile).href) { event.preventDefault(); openSafeExternal(url); } });
  w.webContents.on('will-attach-webview', event => event.preventDefault());
  w.once('ready-to-show', () => { if (isMessage) placeMessage(w, owner); w.show(); if (isMessage) w.focus(); });
  await w.loadFile(indexFile, { query });
  return w;
}
function openSafeExternal(url) { try { const p = new URL(url); if (['https:', 'http:', 'mailto:'].includes(p.protocol)) shell.openExternal(url); } catch { /* Ignore invalid external links. */ } }
async function start() {
  session.defaultSession.setPermissionRequestHandler((_wc, _permission, callback) => callback(false));
  session.defaultSession.setPermissionCheckHandler(() => false);
  store = new SecureStore(app.getPath('userData')); store.load(); service = new GoogleService(store, broadcast, async (name, bytes) => { const { canceled, filePath } = await dialog.showSaveDialog({ defaultPath: path.basename(name) }); if (!canceled && filePath) await fs.writeFile(filePath, bytes); });
  const icon = nativeImage.createFromPath(path.join(directory, '../dist/icon.png')); if (!icon.isEmpty()) app.dock?.setIcon(icon);
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    { label: 'rAIzorMail', submenu: [{ role: 'about' }, { type: 'separator' }, { label: 'Settings…', accelerator: 'CmdOrCtrl+,', click: () => command('settings') }, { type: 'separator' }, { role: 'hide' }, { role: 'hideOthers' }, { role: 'unhide' }, { type: 'separator' }, { role: 'quit' }] },
    { label: 'File', submenu: [{ label: 'New message', accelerator: 'CmdOrCtrl+N', click: () => command('compose') }, { label: 'New event', accelerator: 'CmdOrCtrl+Shift+N', click: () => command('event') }, { type: 'separator' }, { role: 'close' }] },
    { role: 'editMenu' },
    { label: 'View', submenu: [{ label: 'Reading pane', accelerator: 'CmdOrCtrl+Shift+P', click: () => command('preview') }, { label: 'Toggle light / dark', click: () => command('theme') }, { label: 'Mail', accelerator: 'CmdOrCtrl+1', click: () => command('mail') }, { label: 'Calendar', accelerator: 'CmdOrCtrl+2', click: () => command('calendar') }, { type: 'separator' }, { role: 'resetZoom' }, { role: 'zoomIn' }, { role: 'zoomOut' }, { role: 'togglefullscreen' }] },
    { label: 'Message', submenu: [{ label: 'Reply', accelerator: 'CmdOrCtrl+R', click: () => command('reply') }, { label: 'Forward', accelerator: 'CmdOrCtrl+Shift+F', click: () => command('forward') }, { label: 'Move to Trash', click: () => command('trash') }, { label: 'Refresh', accelerator: 'CmdOrCtrl+Shift+R', click: () => command('refresh') }] },
    { role: 'windowMenu' },
    { role: 'help', submenu: [{ label: 'Google connection setup', click: () => command('settings') }] },
  ]));
  const methods = new Set(['listFolders', 'listMessages', 'getMessage', 'materializeAttachments', 'mutate', 'undo', 'send', 'saveDraft', 'listCalendars', 'listEvents', 'saveEvent', 'deleteEvent', 'searchQuery', 'calendarSearchQuery', 'searchEvents', 'assistWriting', 'testGemini', 'createFolder', 'attachment']);
  ipcMain.handle('mail:invoke', async (event, method, input) => {
    if (!trusted(event)) throw new Error('Untrusted request.');
    if (method === 'bootstrap') return { accounts: store.publicAccounts(), config: store.publicConfig() };
    if (method === 'getSignatures') return store.data.signatures || {};
    if (method === 'saveSignature') {
      service.account(input?.accountId);
      const signature = input?.signature;
      if (!signature || typeof signature.text !== 'string' || signature.text.length > 10000 || typeof signature.newMessages !== 'boolean' || typeof signature.replies !== 'boolean') throw new Error('Enter a signature of up to 10,000 characters.');
      store.data.signatures = { ...store.data.signatures, [input.accountId]: { text: signature.text, newMessages: signature.newMessages, replies: signature.replies } }; store.save(); return;
    }
    if (method === 'importGoogle') {
      const { canceled, filePaths } = await dialog.showOpenDialog({ title: 'Choose your Google Desktop OAuth JSON', filters: [{ name: 'Google OAuth credentials', extensions: ['json'] }], properties: ['openFile'] });
      if (canceled) return store.publicConfig();
      const raw = await fs.readFile(filePaths[0], 'utf8'); if (raw.length > 50000) throw new Error('Choose the small OAuth credentials JSON downloaded from Google Cloud.');
      let data; try { data = JSON.parse(raw); } catch { throw new Error('This file is not valid JSON.'); }
      if (!data.installed?.client_id?.endsWith('.apps.googleusercontent.com')) throw new Error('Create an OAuth client of type Desktop app, then import its downloaded JSON.');
      if (store.data.accounts.length && store.data.config.clientId !== data.installed.client_id) throw new Error('Disconnect existing accounts before changing the Google OAuth client.');
      store.data.config.clientId = data.installed.client_id; store.data.config.clientSecret = data.installed.client_secret || ''; store.save(); return store.publicConfig();
    }
    if (method === 'saveGemini') {
      if (input.key && (typeof input.key !== 'string' || input.key.length > 500)) throw new Error('Enter a valid Gemini API key.');
      if (input.model && !/^[a-zA-Z0-9.-]+$/.test(input.model)) throw new Error('Enter a valid Gemini model name.');
      if (input.key?.trim()) store.data.config.geminiKey = input.key.trim();
      if (input.clear) delete store.data.config.geminiKey;
      store.data.config.geminiModel = input.model || 'gemini-3.8-flash'; store.save(); return store.publicConfig();
    }
    if (method === 'connectGoogle') {
      if (signingIn) throw new Error('Google sign-in is already open in your browser.'); signingIn = true;
      try { const a = await connectGoogle(store.data.config, url => shell.openExternal(url)); const old = store.data.accounts.find(x => x.id === a.id); a.color = old?.color || ['#cf8a4c', '#94a88b', '#ccac52', '#91a6bb'][store.data.accounts.length % 4]; if (!a.tokens.refresh_token && old) a.tokens.refresh_token = old.tokens.refresh_token; store.data.accounts = [...store.data.accounts.filter(x => x.id !== a.id), a]; store.save(); broadcast(); return store.publicAccounts(); } finally { signingIn = false; }
    }
    if (method === 'disconnect') { store.data.accounts = store.data.accounts.filter(a => a.id !== input); store.save(); service.forgetAccount(input); broadcast(); return store.publicAccounts(); }
    if (!methods.has(method)) throw new Error('Unknown app action.');
    const multiple = ['listEvents', 'createFolder', 'attachment'].includes(method);
    return multiple && Array.isArray(input) ? service[method](...input) : service[method](input);
  });
  ipcMain.handle('mail:open', async (event, ref, demo) => {
    if (!trusted(event) || typeof ref?.id !== 'string' || typeof ref?.accountId !== 'string') throw new Error('Invalid message.');
    const key = `${demo}:${ref.accountId}:${ref.id}`; const existing = windowKeys.get(key);
    const owner = mainWindow && !mainWindow.isDestroyed() ? mainWindow : BrowserWindow.fromWebContents(event.sender);
    if (existing && !existing.isDestroyed()) { if (existing.isMinimized()) existing.restore(); placeMessage(existing, owner); existing.show(); existing.focus(); return; }
    const w = await createWindow({ message: ref.id, account: ref.accountId, demo: demo ? '1' : '0' }, owner); windowKeys.set(key, w); w.on('closed', () => windowKeys.delete(key));
  });
  ipcMain.on('mail:close', event => { if (trusted(event)) BrowserWindow.fromWebContents(event.sender)?.close(); });
  ipcMain.on('mail:closeGuard', (event, active) => { if (!trusted(event)) return; const w = BrowserWindow.fromWebContents(event.sender); if (w) { if (active === true) closeGuards.add(w.id); else closeGuards.delete(w.id); } });
  ipcMain.on('mail:closeDecision', (event, allow) => {
    if (!trusted(event)) return; const w = BrowserWindow.fromWebContents(event.sender);
    if (!w || exitRequest?.windowId !== w.id) return;
    const kind = exitRequest.kind; exitRequest = null;
    if (allow !== true) return;
    closeGuards.delete(w.id);
    if (kind === 'quit') continueQuit(); else w.close();
  });
  mainWindow = await createWindow(); mainWindow.on('closed', () => { mainWindow = null; });
  app.on('activate', async () => { if (!mainWindow) { mainWindow = await createWindow(); mainWindow.on('closed', () => { mainWindow = null; }); } else mainWindow.show(); });
}
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
