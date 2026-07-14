import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { basename } from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const validator = require('gltf-validator');
const validatorPackage = require('gltf-validator/package.json');

const expectedValidatorVersion = '2.0.0-dev.3.10';
const validatorIdentity = Object.freeze({
  package: 'gltf-validator',
  version: expectedValidatorVersion,
  sourceCommit: 'bcd52cc4ba5f333b2999a58f67cc05ddf28b4fb1',
  license: 'Apache-2.0',
});
const usage =
  'usage: validate_rewritten_glb.mjs --asset <label> --input <glb> ' +
  '[--allowed-warnings <exact-json-array>]';
const knownOptions = new Set([
  '--asset',
  '--input',
  '--allowed-warnings',
]);

function parseArguments(arguments_) {
  const values = new Map();
  for (let index = 0; index < arguments_.length; index += 1) {
    const option = arguments_[index];
    const value = arguments_[index + 1];
    if (!knownOptions.has(option)) {
      throw new Error(`unknown option: ${option ?? '<missing>'}\n${usage}`);
    }
    if (values.has(option)) {
      throw new Error(`duplicate option: ${option}`);
    }
    if (value === undefined) {
      throw new Error(`missing value for option: ${option}\n${usage}`);
    }
    if (knownOptions.has(value)) {
      throw new Error(
        `option ${option} cannot use another option as its value: ${value}`,
      );
    }
    if (value.length === 0) {
      throw new Error(`option ${option} requires a non-empty value`);
    }
    values.set(option, value);
    index += 1;
  }

  const assetLabel = values.get('--asset');
  const inputPath = values.get('--input');
  if (assetLabel === undefined) {
    throw new Error(`missing required option: --asset\n${usage}`);
  }
  if (inputPath === undefined) {
    throw new Error(`missing required option: --input\n${usage}`);
  }
  return {
    assetLabel,
    inputPath,
    allowedWarnings: parseAllowedWarnings(values.get('--allowed-warnings')),
  };
}

function parseAllowedWarnings(value) {
  if (value === undefined) {
    return null;
  }

  let parsed;
  try {
    parsed = JSON.parse(value);
  } catch (error) {
    throw new Error(`--allowed-warnings must be valid JSON: ${formatError(error)}`);
  }
  if (!Array.isArray(parsed)) {
    throw new Error('--allowed-warnings must be a JSON array');
  }
  return parsed.map((warning, index) => normalizeAllowedWarning(warning, index));
}

function normalizeAllowedWarning(warning, index) {
  if (warning === null || typeof warning !== 'object' || Array.isArray(warning)) {
    throw new Error(`allowed warning ${index} must be an object`);
  }
  const allowedKeys = new Set([
    'severity',
    'code',
    'message',
    'pointer',
    'offset',
  ]);
  const unexpectedKey = Object.keys(warning).find((key) => !allowedKeys.has(key));
  if (unexpectedKey !== undefined) {
    throw new Error(`allowed warning ${index} has unknown field: ${unexpectedKey}`);
  }
  if (
    warning.severity !== 1 ||
    typeof warning.code !== 'string' ||
    typeof warning.message !== 'string' ||
    ('pointer' in warning && typeof warning.pointer !== 'string') ||
    ('offset' in warning &&
      (!Number.isSafeInteger(warning.offset) || warning.offset < 0))
  ) {
    throw new Error(
      `allowed warning ${index} must exactly match normalized validator fields`,
    );
  }
  return normalizeIssue(warning);
}

function normalizeIssue(issue) {
  const normalized = {
    severity: issue.severity,
    code: issue.code,
    message: issue.message,
  };
  if (issue.pointer !== undefined) {
    normalized.pointer = issue.pointer;
  }
  if (issue.offset !== undefined) {
    normalized.offset = issue.offset;
  }
  return normalized;
}

function compareMessages(left, right) {
  return (
    left.severity - right.severity ||
    left.code.localeCompare(right.code) ||
    compareOptionalStrings(left.pointer, right.pointer) ||
    compareOptionalNumbers(left.offset, right.offset) ||
    left.message.localeCompare(right.message)
  );
}

function compareOptionalStrings(left, right) {
  if (left === undefined || right === undefined) {
    return left === right ? 0 : left === undefined ? -1 : 1;
  }
  return left.localeCompare(right);
}

function compareOptionalNumbers(left, right) {
  if (left === undefined || right === undefined) {
    return left === right ? 0 : left === undefined ? -1 : 1;
  }
  return left - right;
}

function warningAllowListMatches(messages, allowedWarnings) {
  const warnings = messages.filter((message) => message.severity === 1);
  if (allowedWarnings === null) {
    return warnings.length === 0;
  }
  const sortedAllowedWarnings = [...allowedWarnings].sort(compareMessages);
  return JSON.stringify(warnings) === JSON.stringify(sortedAllowedWarnings);
}

function formatError(error) {
  if (error instanceof Error && error.message.length > 0) {
    return error.message;
  }
  if (typeof error === 'string' && error.length > 0) {
    return error;
  }
  try {
    return JSON.stringify(error);
  } catch {
    return String(error);
  }
}

async function main() {
  if (validatorPackage.version !== expectedValidatorVersion) {
    throw new Error(
      `expected gltf-validator ${expectedValidatorVersion}, found ${validatorPackage.version}`,
    );
  }

  const { assetLabel, inputPath, allowedWarnings } = parseArguments(
    process.argv.slice(2),
  );
  const bytes = await readFile(inputPath);
  const result = await validator.validateBytes(new Uint8Array(bytes), {
    uri: basename(inputPath),
  });
  const messages = result.issues.messages
    .map(normalizeIssue)
    .sort(compareMessages);

  const report = {
    validator: validatorIdentity,
    asset: {
      label: assetLabel,
      sha256: createHash('sha256').update(bytes).digest('hex'),
    },
    issues: {
      errors: result.issues.numErrors,
      warnings: result.issues.numWarnings,
      infos: result.issues.numInfos,
      hints: result.issues.numHints,
      messages,
    },
  };
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (
    result.issues.numErrors > 0 ||
    !warningAllowListMatches(messages, allowedWarnings)
  ) {
    process.stderr.write(
      `validation failed with ${result.issues.numErrors} error(s) and ` +
        `${result.issues.numWarnings} warning(s); inspect stdout JSON\n`,
    );
    process.exitCode = 1;
  }
}

main().catch((error) => {
  process.stderr.write(`validation runner failed: ${formatError(error)}\n`);
  process.exitCode = 1;
});
