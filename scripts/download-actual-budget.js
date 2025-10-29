const api = require('@actual-app/api');
const path = require('path');
const { execSync } = require('child_process');
const argv = require('minimist')(process.argv.slice(2));

// Parse arguments using minimist
const dataDir = argv.dataDir || '/tmp/actual-download';
const destDir = argv.destDir || '/data/backup';
const serverURL = argv.serverURL || 'http://localhost:5006';
const password = argv.password || 'password';
const syncIdList = (argv.syncIds || '').split(',');
const e2ePasswords = (argv.e2ePasswords || '').split(',');
const now = argv.now || 'now';

console.log("📥 Starting download from", serverURL);
console.log("🗂 Sync IDs:", syncIdList);

(async () => {
    for (let i = 0; i < syncIdList.length; i++) {
        const syncId = syncIdList[i];
        if (!syncId) continue;

        const e2ePassword = e2ePasswords[i] || null;
        const zipPath = path.join(destDir, `backup.${syncId}.${now}.zip`);

        console.log(`⬇️  Downloading budget ${syncId} -> ${zipPath}`);

        await api.init({ dataDir, serverURL, password });

        try {
            await api.downloadBudget(syncId, e2ePassword ? { password: e2ePassword } : {});
            console.log(`✅ Budget ${syncId} downloaded successfully.`);
            await api.getAccounts();
            await api.shutdown();

            // Zip the downloaded data
            execSync(`cd ${dataDir} && zip -r ${zipPath} .`, { stdio: 'inherit' });
            console.log(`📦 Created zip: ${zipPath}`);
        } catch (err) {
            console.error(`❌ Failed to download ${syncId}:`, err);
        } finally {
            await api.shutdown();
        }
    }

    console.log("🎉 All downloads completed!");
})();
