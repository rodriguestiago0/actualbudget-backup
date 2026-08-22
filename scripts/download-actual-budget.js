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
const zipEnable = argv.zipEnable !== 'FALSE';
const zipType = argv.zipType === '7z' ? '7z' : 'zip';
const zipPassword = argv.zipPassword || '';

console.log("📥 Starting download from", serverURL);
console.log("🗂 Sync IDs:", syncIdList);
console.log("📦 Archive format:", zipEnable ? zipType : 'none (uncompressed)');
console.log("🔒 Password protection:", zipPassword ? 'enabled' : 'disabled');

function buildArchiveCommand(sourceDir, zipPath) {
    if (!zipEnable) {
        // uncompressed: use tar (no password support)
        return `cd ${sourceDir} && tar -cf ${zipPath} .`;
    }
    if (zipType === '7z') {
        const pwFlag = zipPassword ? `-p"${zipPassword}" -mhe=on` : '';
        return `cd ${sourceDir} && 7z a -t7z -m0=lzma2 -mx=9 -mfb=64 -md=32m -ms=on ${pwFlag} "${zipPath}" .`;
    }
    // zip
    const pwFlag = zipPassword ? `-p"${zipPassword}"` : '';
    return `cd ${sourceDir} && 7z a -tzip -mx=9 ${pwFlag} "${zipPath}" .`;
}

function archiveExtension() {
    if (!zipEnable) return 'tar';
    return zipType;
}

(async () => {
    const ext = archiveExtension();

    for (let i = 0; i < syncIdList.length; i++) {
        const syncId = syncIdList[i];
        if (!syncId) continue;

        const e2ePassword = e2ePasswords[i] || null;
        const archivePath = path.join(destDir, `backup.${syncId}.${now}.${ext}`);

        console.log(`⬇️  Downloading budget ${syncId} -> ${archivePath}`);

        await api.init({ dataDir, serverURL, password });

        try {
            await api.downloadBudget(syncId, e2ePassword ? { password: e2ePassword } : {});
            console.log(`✅ Budget ${syncId} downloaded successfully.`);
            await api.getAccounts();
            await api.shutdown();

            // Create the archive
            const cmd = buildArchiveCommand(dataDir, archivePath);
            console.log(`📦 Creating archive: ${archivePath}`);
            execSync(cmd, { stdio: 'inherit' });
            execSync(`rm -rf ${dataDir}/*`, { stdio: 'inherit' });
            console.log(`📦 Archive created: ${archivePath}`);
        } catch (err) {
            console.error(`❌ Failed to download ${syncId}:`, err);
        } finally {
            await api.shutdown();
        }
    }

    console.log("🎉 All downloads completed!");
})();
