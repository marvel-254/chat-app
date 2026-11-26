import { writeFileSync } from 'node:fs';

const config = {
  apiKey: process.env.FIREBASE_WEB_API_KEY,
  appId: process.env.FIREBASE_WEB_APP_ID,
  messagingSenderId: process.env.FIREBASE_WEB_SENDER_ID,
  projectId: process.env.FIREBASE_WEB_PROJECT_ID,
};
const enabled = Boolean(process.env.FIREBASE_WEB_VAPID_KEY && Object.values(config).every(Boolean));
const appVersion = process.argv[3] || 'dev';
writeFileSync(
  process.argv[2],
  `self.BRO_APP_VERSION = ${JSON.stringify(appVersion)};\n` +
    `self.BRO_FIREBASE_CONFIG = ${JSON.stringify(enabled ? config : null)};\n`,
);
