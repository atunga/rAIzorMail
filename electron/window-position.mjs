// All bounds are Electron device-independent coordinates, including negative monitors.
export function messageBounds(owner, workArea, size = { width: 900, height: 800 }) {
  const width = Math.min(size.width, workArea.width);
  const height = Math.min(size.height, workArea.height);
  const x = Math.round(owner.x + (owner.width - width) / 2);
  const y = Math.round(owner.y + (owner.height - height) / 2);
  return { x: Math.max(workArea.x, Math.min(x, workArea.x + workArea.width - width)), y: Math.max(workArea.y, Math.min(y, workArea.y + workArea.height - height)), width, height };
}
