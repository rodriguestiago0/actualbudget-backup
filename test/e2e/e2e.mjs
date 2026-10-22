// Helpers for test/e2e/run.sh, run with the image's Node and @actual-app/api.
//
//   seed <fixture> <sync id file>        create the fixture budget on the server
//   snapshot-server <sync id> <out>      dump the budget as the server has it
//   snapshot-backup <budget dir> <out>   dump a budget unpacked from a backup
//   compare <fixture> <server> <backup>  check both dumps match the fixture
//
// The server is read from ACTUAL_SERVER_URL and ACTUAL_PASSWORD.
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { isDeepStrictEqual } from 'node:util';

import * as api from '@actual-app/api';

const [command, ...args] = process.argv.slice(2);
const server = { serverURL: process.env.ACTUAL_SERVER_URL, password: process.env.ACTUAL_PASSWORD };

const readJson = (path) => JSON.parse(readFileSync(path, 'utf8'));
const byName = (a, b) => a.name.localeCompare(b.name);

async function withApi(config, func) {
  const dataDir = mkdtempSync(join(tmpdir(), 'e2e-'));
  await api.init({ dataDir, ...config });
  try {
    return await func(dataDir);
  } finally {
    await api.shutdown();
  }
}

async function seed(fixturePath, syncIdPath) {
  const fixture = readJson(fixturePath);

  await withApi(server, async () => {
    await api.runImport(fixture.name, async () => {
      const categoryIds = {};
      for (const group of fixture.categoryGroups) {
        const groupId = await api.createCategoryGroup({ name: group.name });
        for (const name of group.categories) {
          categoryIds[name] = await api.createCategory({ name, group_id: groupId });
        }
      }

      for (const account of fixture.accounts) {
        const accountId = await api.createAccount({ name: account.name, offbudget: account.offbudget }, 0);
        await api.addTransactions(
          accountId,
          account.transactions.map((t) => ({
            date: t.date,
            amount: t.amount,
            payee_name: t.payee,
            category: t.category && categoryIds[t.category],
            notes: t.notes,
          })),
        );
      }

      for (const { month, category, amount } of fixture.budget) {
        await api.setBudgetAmount(month, categoryIds[category], amount);
      }
    });

    const budget = (await api.getBudgets()).find((b) => b.name === fixture.name && b.groupId);
    if (!budget) throw new Error('the seeded budget was not uploaded to the server');
    writeFileSync(syncIdPath, budget.groupId);
  });
}

// Everything the fixture sets, read back through the API
async function snapshot() {
  const payees = Object.fromEntries((await api.getPayees()).map((p) => [p.id, p.name]));
  const categories = Object.fromEntries((await api.getCategories()).map((c) => [c.id, c.name]));

  const accounts = [];
  for (const account of (await api.getAccounts()).sort(byName)) {
    const transactions = (await api.getTransactions(account.id, '1970-01-01', '2100-12-31'))
      .map((t) => ({
        date: t.date,
        amount: t.amount,
        payee: payees[t.payee] ?? null,
        category: categories[t.category] ?? null,
        notes: t.notes ?? null,
      }))
      .sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));

    accounts.push({
      name: account.name,
      offbudget: Boolean(account.offbudget),
      closed: Boolean(account.closed),
      balance: await api.getAccountBalance(account.id),
      transactions,
    });
  }

  const categoryGroups = (await api.getCategoryGroups())
    .map((g) => ({ name: g.name, categories: (g.categories ?? []).map((c) => c.name).sort() }))
    .sort(byName);

  const budget = {};
  for (const month of await api.getBudgetMonths()) {
    for (const group of (await api.getBudgetMonth(month)).categoryGroups) {
      for (const category of group.categories) {
        if (category.budgeted) budget[`${month} ${category.name}`] = category.budgeted;
      }
    }
  }

  return { accounts, categoryGroups, budget };
}

async function snapshotServer(syncId, outPath) {
  await withApi(server, async () => {
    await api.downloadBudget(syncId);
    writeFileSync(outPath, JSON.stringify(await snapshot(), null, 2));
  });
}

// Loads the unpacked backup offline, as Actual would after an import
async function snapshotBackup(budgetDir, outPath) {
  const { id } = readJson(join(budgetDir, 'metadata.json'));

  await withApi({}, async (dataDir) => {
    mkdirSync(join(dataDir, id));
    for (const file of ['db.sqlite', 'metadata.json']) {
      copyFileSync(join(budgetDir, file), join(dataDir, id, file));
    }
    await api.loadBudget(id);
    writeFileSync(outPath, JSON.stringify(await snapshot(), null, 2));
  });
}

function compare(fixturePath, serverPath, backupPath) {
  const fixture = readJson(fixturePath);
  const fromServer = readJson(serverPath);
  const fromBackup = readJson(backupPath);
  const errors = [];

  if (!isDeepStrictEqual(fromServer, fromBackup)) {
    errors.push('the backup differs from the budget on the server');
  }

  // so an empty server and an empty backup don't pass as equal
  for (const account of fixture.accounts) {
    const found = fromBackup.accounts.find((a) => a.name === account.name);
    if (!found) {
      errors.push(`account "${account.name}" is missing`);
      continue;
    }
    const balance = account.transactions.reduce((sum, t) => sum + t.amount, 0);
    if (found.balance !== balance) errors.push(`"${account.name}" balance is ${found.balance}, expected ${balance}`);
    if (found.offbudget !== account.offbudget) errors.push(`"${account.name}" offbudget is ${found.offbudget}`);
    for (const t of account.transactions) {
      const match = found.transactions.some(
        (f) => f.date === t.date && f.amount === t.amount && f.payee === t.payee &&
          f.category === (t.category ?? null) && f.notes === (t.notes ?? null),
      );
      if (!match) errors.push(`"${account.name}" is missing the transaction ${JSON.stringify(t)}`);
    }
  }

  for (const group of fixture.categoryGroups) {
    const found = fromBackup.categoryGroups.find((g) => g.name === group.name);
    if (!isDeepStrictEqual(found?.categories, [...group.categories].sort())) {
      errors.push(`category group "${group.name}" is ${JSON.stringify(found)}`);
    }
  }

  for (const { month, category, amount } of fixture.budget) {
    const found = fromBackup.budget[`${month} ${category}`];
    if (found !== amount) errors.push(`budgeted ${category} in ${month} is ${found}, expected ${amount}`);
  }

  if (errors.length > 0) {
    console.error(errors.join('\n'));
    process.exit(1);
  }
  const count = fromBackup.accounts.reduce((sum, a) => sum + a.transactions.length, 0);
  console.log(`backup matches the server: ${fromBackup.accounts.length} accounts, ${count} transactions`);
}

const commands = {
  seed,
  'snapshot-server': snapshotServer,
  'snapshot-backup': snapshotBackup,
  compare,
};

if (!commands[command]) {
  console.error(`unknown command "${command}"`);
  process.exit(2);
}
await commands[command](...args);
