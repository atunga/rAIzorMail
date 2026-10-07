import type { Attachment } from './types';
export const attachmentLimit = 18 * 1024 * 1024;
export async function readAttachments(files: File[], existingBytes: number): Promise<Attachment[]> {
  if (existingBytes + files.reduce((total, file) => total + file.size, 0) > attachmentLimit) throw new Error('Keep attachments below 18 MB per message.');
  return Promise.all(files.map(async file => {
    let buffer: ArrayBuffer;
    try { buffer = await file.arrayBuffer(); } catch { throw new Error(`Could not read ${file.name}. Choose a file, or zip a folder before attaching it.`); }
    const bytes = new Uint8Array(buffer); let binary = '';
    for (let offset = 0; offset < bytes.length; offset += 8192) binary += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
    return { id: crypto.randomUUID(), name: file.name, size: file.size, mimeType: file.type || 'application/octet-stream', data: btoa(binary) };
  }));
}
