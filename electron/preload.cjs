const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('desktop', {
  invoke: (method, input) => ipcRenderer.invoke('mail:invoke', method, input),
  openMessage: (ref, demo) => ipcRenderer.invoke('mail:open', ref, demo),
  closeWindow: () => ipcRenderer.send('mail:close'),
  setCloseGuard: active => ipcRenderer.send('mail:closeGuard', active),
  resolveClose: allow => ipcRenderer.send('mail:closeDecision', allow),
  onRequestClose: callback => { const handler = () => callback(); ipcRenderer.on('mail:requestClose', handler); return () => ipcRenderer.removeListener('mail:requestClose', handler); },
  onCommand: callback => { const handler = (_, command) => callback(command); ipcRenderer.on('mail:command', handler); return () => ipcRenderer.removeListener('mail:command', handler); },
  onChanged: callback => { const handler = (_, change) => callback(change); ipcRenderer.on('mail:changed', handler); return () => ipcRenderer.removeListener('mail:changed', handler); },
});
