# FeeSharesMinter — CRE workflow

Off-chain workflow that drives the [`FeeSharesMinter`](../src/FeeSharesMinter.sol) on-chain robot. On every cron tick, for each configured `(minter, hub, assetId)` target:

1. Call `checkUpkeep(abi.encode(hub, assetId))` on the robot.
2. If `upkeepNeeded === true`, estimate gas for `onReport` (skip on revert).
3. Sign the returned `performData` and call `writeReport(receiver=minter, report)`.

Because `FeeSharesMinter.onReport` is **permissionless**, no `MailboxCRE` intermediary is needed — the report is delivered directly to the robot.

The on-chain ABI is sourced from a checked-in `as const` TypeScript file at [`workflows/shared/offchain/abi/IAaveCREReceiver.ts`](../../shared/offchain/abi/IAaveCREReceiver.ts), generated from the Solidity interface via `npm run generate-abis` at the repo root. The TS code never re-declares ABIs — when the interface changes, regenerate and commit.

## Config schema

```jsonc
{
  "schedule": "*/5 * * * *",
  "evms": [
    {
      "chainName": "ethereum-mainnet",
      "targets": [
        {
          "minter": "0x...",   // deployed FeeSharesMinter address
          "hub": "0x...",      // Aave V4 Hub to mint on (e.g. CORE_HUB)
          "assetId": 0          // asset id within that Hub
        }
      ]
    }
  ]
}
```

Add one entry to `targets` per `(hub, assetId)` pair you want to monitor. The same workflow handles multiple targets and multiple chains.

## Local commands

```bash
# install offchain deps (uses repo-root .npmrc — 7-day maturity gate + exact pins)
cd workflows/fee-shares-minter/offchain
npm install
npm run typecheck
```

## Simulate / deploy

Run from the repository's `workflows/` directory (where `project.yaml` lives):

```bash
cre workflow simulate ./fee-shares-minter/offchain --target=staging-settings
cre workflow deploy   ./fee-shares-minter/offchain --target=production-settings
```
