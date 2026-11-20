import { writeFileSync } from 'node:fs';

const config = {
  apiKey: process.env.FIREBASE_WEB_API_KEY,
  appId: process.env.FIREBASE_WEB_APP_ID,
  messagingSenderId: process.env.FIREBASE_WEB_SENDER_ID,
  projectId: process.env.FIREBASE_WEB_PROJECT_ID,
};
const enabled = Boolean(process.env.FIREBASE_WEB_VAPID_KEY && Object.values(config).every(Boolean));
writeFileSync(process.argv[2], `self.BRO_FIREBASE_CONFIG = ${JSON.stringify(enabled ? config : null)};\n`);
