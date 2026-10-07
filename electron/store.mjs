import { safeStorage } from 'electron';
import fs from 'node:fs';
import path from 'node:path';
export class SecureStore {
  constructor(directory) { this.file = path.join(directory, 'accounts.enc'); this.data = { accounts: [], config: { geminiModel: 'gemini-3.8-flash' } }; }
  load() { if (fs.existsSync(this.file)) { if (!safeStorage.isEncryptionAvailable()) throw new Error('macOS secure storage is unavailable. Unlock your keychain and restart rAIzorMail.'); this.data = JSON.parse(safeStorage.decryptString(fs.readFileSync(this.file))); } return this.data; }
  save() { if (!safeStorage.isEncryptionAvailable()) throw new Error('macOS secure storage is unavailable. Your credentials were not saved.'); fs.mkdirSync(path.dirname(this.file), { recursive: true }); const temp = `${this.file}.tmp`; fs.writeFileSync(temp, safeStorage.encryptString(JSON.stringify(this.data)), { mode: 0o600 }); fs.renameSync(temp, this.file); }
  publicConfig() { return { googleConfigured: !!this.data.config.clientId, geminiConfigured: !!this.data.config.geminiKey, geminiModel: (!this.data.config.geminiKey && this.data.config.geminiModel === 'gemini-2.5-flash' ? 'gemini-3.8-flash' : this.data.config.geminiModel) || 'gemini-3.8-flash' }; }
  publicAccounts() { return this.data.accounts.map(({ id, email, name, color }) => ({ id, email, name, color })); }
}
