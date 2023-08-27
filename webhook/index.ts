import express from 'express';
import crypto from 'crypto';
import dotenv from 'dotenv';
import * as fs from 'fs';
import * as https from "https";

dotenv.config();

const app = express();
app.use(express.json());

const SERVICE_PORT=process.env.SERVICE_PORT || 4000;
const HOME_DIR=process.env.HOME_DIR || '/home/ubuntu/orchestration';
const LOG_DIR_PREFIX=process.env.LOG_DIR_PREFIX || '/var/log/lens-sandbox-';
const TELEGRAM_BOT_TOKEN=process.env.TELEGRAM_BOT_TOKEN
const TELEGRAM_CHAT_ID=process.env.TELEGRAM_CHAT_ID

app.post('/:route', async (req, res, next) => {
  const servicename = req.params.route;
  const SECRET = process.env['WEBHOOK_SECRET_' + servicename.toUpperCase()] || process.env.WEBHOOK_SECRET as string;

  const sig = req.headers['x-hub-signature-256'];
  const hmac = crypto.createHmac('sha256', SECRET);
  const digest = 'sha256=' + hmac.update(JSON.stringify(req.body)).digest('hex');
  const check = Buffer.from(digest).equals(Buffer.from(sig as string));

  if (!check) {
    console.log('Error: Invalid X-Hub-Signature-256');
    res.status(403);
    res.send('Error: Invalid X-Hub-Signature-256');
    return;
  } else {
    console.log('Webhook received and is processing');
    res.status(200).send('Webhook received and is processing');

    process.chdir(`${HOME_DIR}`);
    const spawn = require('child_process').spawn;
    const rebuild = spawn(`${HOME_DIR}/8-rebuild.sh`, ['sandbox-' + servicename, '-y']);

    const rebuildLog = fs.createWriteStream(`${LOG_DIR_PREFIX}${servicename}/rebuild.log`, { flags: 'a' });
    rebuild.stdout.pipe(rebuildLog, { end: false });
    rebuild.stderr.pipe(rebuildLog, { end: false });
    
    // Listen for close event to ensure that rebuild completes before starting api server
    rebuild.on('close', (code: number) => {
      if (code !== 0) {
        console.log(`rebuild process exited with code ${code}`);
      } else {
        console.log('rebuild completed successfully, starting api server');
        
        process.chdir(`${HOME_DIR}`);
        const startserver = spawn(`${HOME_DIR}/4-startserver.sh`, ['sandbox-' + servicename]);
        const startserverLog = fs.createWriteStream(`${LOG_DIR_PREFIX}${servicename}/startserver.log`, { flags: 'a' });
        startserver.stdout.pipe(startserverLog, { end: false });
        startserver.stderr.pipe(startserverLog, { end: false });
        
        startserver.on('close', (startserverCode: number) => {
          if (startserverCode !== 0) {
            console.log(`startserver process exited with code ${startserverCode}`);
          } else {
            console.log('startserver completed successfully, starting yarn compute');

            process.chdir(`${HOME_DIR}/sandbox-${servicename}/ts-lens`);
            const yarn = spawn('yarn', ['compute']);
            const computeLog = fs.createWriteStream(`${LOG_DIR_PREFIX}${servicename}/compute.log`, { flags: 'a' });
            yarn.stdout.pipe(computeLog, { end: false });
            yarn.stderr.pipe(computeLog, { end: false });

            let msg: string
            yarn.on('close', (yarnCode: number) => {
              if (yarnCode != 0) {
                msg = `compute process exited with code ${yarnCode}`
              } else {
                msg = 'compute completed successfully'
              }
              console.log(msg);
              const telegramUrl = `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}`
                                    + `/sendMessage?chat_id=${TELEGRAM_CHAT_ID}&text=${msg}`;
              (async () => {
                const response = await https.request(telegramUrl);
                const body = await response.text();
                console.log(body)
              })();
            });
          }
        });
      }
    });
  }
});

app.listen(SERVICE_PORT, () => console.log('Server is ready to handle GitHub webhooks on port',SERVICE_PORT));
