import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Yalnızca yerel: host açılmaz (0.0.0.0 değil), panel ağa servis edilmez.
// Canlı veriye bakan bir araç; LAN'daki başka bir cihaza açılması istenmez.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5273,
    host: '127.0.0.1',
    strictPort: true,
  },
});
