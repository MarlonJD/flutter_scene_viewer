import {
  hashBytes,
  generateControlledStudioHdr,
  loadControlledComparisonState,
} from './plan015_controlled_comparison_contract.mjs';

const state = loadControlledComparisonState();
const bytes = generateControlledStudioHdr(state);
process.stdout.write(`${hashBytes(bytes)}\n`);
