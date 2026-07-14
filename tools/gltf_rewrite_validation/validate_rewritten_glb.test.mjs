import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const harnessDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(harnessDirectory, '../..');
const runner = join(harnessDirectory, 'validate_rewritten_glb.mjs');
const validFixture = join(repositoryRoot, 'test/fixtures/Box.glb');

function runRunner(arguments_) {
  return spawnSync(process.execPath, [runner, ...arguments_], {
    cwd: repositoryRoot,
    encoding: 'utf8',
  });
}

function temporaryFile(t, name, bytes) {
  const directory = mkdtempSync(join(tmpdir(), 'fsv-validator-test-'));
  t.after(() => rmSync(directory, { force: true, recursive: true }));
  const path = join(directory, name);
  writeFileSync(path, bytes);
  return path;
}

function glbWithJson(json) {
  const jsonBytes = Buffer.from(JSON.stringify(json));
  const paddedLength = (jsonBytes.length + 3) & ~3;
  const bytes = Buffer.alloc(20 + paddedLength, 0x20);
  bytes.writeUInt32LE(0x46546c67, 0);
  bytes.writeUInt32LE(2, 4);
  bytes.writeUInt32LE(bytes.length, 8);
  bytes.writeUInt32LE(paddedLength, 12);
  bytes.writeUInt32LE(0x4e4f534a, 16);
  jsonBytes.copy(bytes, 20);
  return bytes;
}

test('validator errors print normalized JSON before exiting nonzero', (t) => {
  const validBytes = readFileSync(validFixture);
  const input = temporaryFile(
    t,
    'truncated.glb',
    validBytes.subarray(0, validBytes.length - 7),
  );

  const result = runRunner(['--asset', 'truncated', '--input', input]);

  assert.equal(result.status, 1);
  const report = JSON.parse(result.stdout);
  assert.equal(report.issues.errors, 1);
  assert.deepEqual(report.issues.messages, [
    {
      severity: 0,
      code: 'GLB_UNEXPECTED_END_OF_CHUNK_DATA',
      message: 'Unexpected end of chunk data.',
      offset: validBytes.length - 7,
    },
  ]);
});

test('warnings fail unless an exact caller allow-list disposes every warning', (t) => {
  const input = temporaryFile(
    t,
    'warning.glb',
    glbWithJson({ asset: { version: '2.0' }, unexpected: true }),
  );
  const warning = {
    severity: 1,
    code: 'UNEXPECTED_PROPERTY',
    message: 'Unexpected property.',
    pointer: '/unexpected',
  };

  const rejected = runRunner(['--asset', 'warning', '--input', input]);
  assert.equal(rejected.status, 1);
  assert.deepEqual(JSON.parse(rejected.stdout).issues.messages, [warning]);

  const allowed = runRunner([
    '--asset',
    'warning',
    '--input',
    input,
    '--allowed-warnings',
    JSON.stringify([warning]),
  ]);
  assert.equal(allowed.status, 0, allowed.stderr);

  const staleAllowList = runRunner([
    '--asset',
    'warning',
    '--input',
    input,
    '--allowed-warnings',
    JSON.stringify([{ ...warning, pointer: '/different' }]),
  ]);
  assert.equal(staleAllowList.status, 1);
});

test('malformed command-line options are rejected', () => {
  const cases = [
    ['empty asset', ['--asset', '', '--input', validFixture]],
    ['empty input', ['--asset', 'box', '--input', '']],
    [
      'duplicate flag',
      ['--asset', 'box', '--asset', 'other', '--input', validFixture],
    ],
    ['missing flag', ['--asset', 'box']],
    ['missing value', ['--asset', 'box', '--input']],
    ['unknown flag', ['--asset', 'box', '--wat', validFixture]],
    [
      'known option used as asset value',
      ['--asset', '--input', '--input', validFixture],
    ],
    [
      'known option used as input value',
      ['--asset', 'box', '--input', '--asset'],
    ],
  ];

  for (const [name, arguments_] of cases) {
    const result = runRunner(arguments_);
    assert.equal(result.status, 1, `${name}: ${result.stdout}${result.stderr}`);
    assert.match(result.stderr, /\S/, `${name}: expected actionable stderr`);
    assert.doesNotMatch(result.stderr, /^undefined\s*$/);
  }
});
