-include .env

update :; forge update
install :; forge install && npm install && npm --prefix workflows/shared/offchain install && npm --prefix workflows/fee-shares-minter/offchain install

build :; forge build --sizes
test :; forge test -vvv --ffi
test-unit :; forge test --no-match-contract 'Fork' -vvv
test-fork :; forge test --match-contract 'Fork' -vvv --ffi
gas-snapshot :; forge snapshot --match-contract 'FeeSharesMinter'

generate-abis :; npm run generate-abis

typecheck-fee-shares-minter :; cd workflows/fee-shares-minter/offchain && npm run typecheck

# `cast wallet import <name>` first, then set ACCOUNT_NAME in .env.
deploy-account :; forge script ${contract} --rpc-url ${chain} --account ${ACCOUNT_NAME} -vvvv --slow $(if ${dry},,--verify --broadcast)

deploy-mainnet-fee-shares-minter :; make deploy-account contract=workflows/fee-shares-minter/scripts/DeployFeeSharesMinter.s.sol:DeployMainnet chain=mainnet
deploy-mainnet-fee-shares-minter-dry :; make deploy-account contract=workflows/fee-shares-minter/scripts/DeployFeeSharesMinter.s.sol:DeployMainnet chain=mainnet dry=1
