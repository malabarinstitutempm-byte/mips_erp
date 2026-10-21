import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';
import fs from 'fs';
import path from 'path';

function authSyncPlugin(): Plugin {
  return {
    name: 'auth-sync-plugin',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        // Handle CORS headers for Flutter web / cross-origin requests
        res.setHeader('Access-Control-Allow-Origin', '*');
        res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

        if (req.method === 'OPTIONS') {
          res.statusCode = 204;
          res.end();
          return;
        }

        if (req.url && (req.url === '/api/account-sync' || req.url.startsWith('/api/account-sync?'))) {
          const filePath = path.resolve(__dirname, '.auth_sync.json');

          if (req.method === 'GET') {
            try {
              if (fs.existsSync(filePath)) {
                const data = fs.readFileSync(filePath, 'utf-8');
                res.setHeader('Content-Type', 'application/json');
                res.end(data || '{}');
                return;
              }
            } catch (_) {}
            res.setHeader('Content-Type', 'application/json');
            res.end(JSON.stringify({}));
            return;
          }

          if (req.method === 'POST') {
            let body = '';
            req.on('data', (chunk) => {
              body += chunk;
            });
            req.on('end', () => {
              try {
                let existing: Record<string, any> = {};
                if (fs.existsSync(filePath)) {
                  try {
                    existing = JSON.parse(fs.readFileSync(filePath, 'utf-8'));
                  } catch (_) {}
                }
                const incoming = JSON.parse(body || '{}');
                if (incoming.identifier) {
                  const key = String(incoming.identifier).trim().toLowerCase();
                  existing[key] = {
                    ...(existing[key] || {}),
                    ...incoming,
                    identifier: key,
                    updatedAt: new Date().toISOString(),
                  };
                } else if (typeof incoming === 'object') {
                  Object.keys(incoming).forEach((k) => {
                    const normK = k.trim().toLowerCase();
                    existing[normK] = {
                      ...(existing[normK] || {}),
                      ...incoming[k],
                      identifier: normK,
                      updatedAt: new Date().toISOString(),
                    };
                  });
                }
                fs.writeFileSync(filePath, JSON.stringify(existing, null, 2), 'utf-8');
                res.setHeader('Content-Type', 'application/json');
                res.end(JSON.stringify({ success: true, accounts: existing }));
              } catch (err: any) {
                res.statusCode = 400;
                res.setHeader('Content-Type', 'application/json');
                res.end(JSON.stringify({ error: err?.message || 'Invalid JSON' }));
              }
            });
            return;
          }
        }

        next();
      });
    },
  };
}

export default defineConfig({
  plugins: [
    authSyncPlugin(),
    react(),
    VitePWA({
      registerType: 'prompt',
      includeAssets: ['logo.png'],
      manifest: {
        name: 'MIPS Portal',
        short_name: 'MIPS',
        description: 'Malabar Institute of Paramedical Science Teacher & Student Portal',
        theme_color: '#0B2A4A',
        background_color: '#F7F9FC',
        display: 'standalone',
        orientation: 'portrait',
        start_url: '/',
        icons: [
          {
            src: '/logo.png',
            sizes: '192x192',
            type: 'image/png',
          },
          {
            src: '/logo.png',
            sizes: '512x512',
            type: 'image/png',
          },
          {
            src: '/logo.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable',
          },
        ],
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,ico,png,svg,woff2}'],
        navigateFallback: '/index.html',
        runtimeCaching: [
          {
            urlPattern: /^https:\/\/fonts\.(?:googleapis|gstatic)\.com\/.*/i,
            handler: 'CacheFirst',
            options: {
              cacheName: 'google-fonts',
              expiration: {
                maxEntries: 10,
                maxAgeSeconds: 60 * 60 * 24 * 365,
              },
            },
          },
        ],
      },
    }),
  ],
  build: {
    target: 'es2022',
    cssCodeSplit: true,
    sourcemap: false,
    chunkSizeWarningLimit: 600,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (
            id.includes('node_modules/react/') ||
            id.includes('node_modules/react-dom/') ||
            id.includes('node_modules/react-router-dom/') ||
            id.includes('node_modules/react-router/')
          ) {
            return 'vendor-react';
          }
          if (id.includes('node_modules/@supabase/')) {
            return 'vendor-supabase';
          }
          if (id.includes('node_modules/@tanstack/react-query')) {
            return 'vendor-query';
          }
          if (id.includes('node_modules/lucide-react/')) {
            return 'vendor-icons';
          }
        },
      },
    },
  },
  server: { port: 3000 },
});
