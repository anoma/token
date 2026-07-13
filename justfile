# Show commands before running (helps debug failures)
set shell := ["bash", "-euo", "pipefail", "-c"]

# Default recipe
default:
    @just --list

# Install/update git submodule dependencies
deps:
    git submodule update --init --recursive

# Install test tooling (solhint, etc.)
tooling:
    bun install

# Clean build artifacts
clean:
    forge clean

# Build contracts
build *args:
    forge build --sizes --ast {{ args }}

# Format contracts
fmt *args:
    forge fmt {{ args }}

# Check contract formatting
fmt-check:
    forge fmt --check

# Lint contracts (solhint)
lint:
    bunx --bun solhint --config .solhint.json 'src/**/*.sol'
    bunx --bun solhint --config .solhint.other.json 'test/**/*.sol'
    bunx --bun solhint --config .solhint.other.json 'script/**/*.sol'

# Static analysis with slither
static-analysis:
    slither .

# Run contract tests
test *args:
    forge test --force {{ args }}

# Prerequisites check (mirrors CI)
check:
    @echo "==> Checking formatting..."
    @just fmt-check
    @echo "==> Linting..."
    @just lint
    @echo "==> Static analysis with slither..."
    @just static-analysis
    @echo "==> Cleaning..."
    @just clean
    @echo "==> Building..."
    @just build
    @echo "==> Testing..."
    @just test

# --- Deployment ---

# Simulate the XanV1 deployment (dry-run)
deploy-simulate initial-mint-recipient council chain *args:
    @echo "Cleaning contracts to ensure reproducible build..."
    @just clean
    forge script script/DeployXanV1.s.sol:DeployXanV1 \
        --sig "run(address,address)" {{ initial-mint-recipient }} {{ council }} \
        --rpc-url {{ chain }} {{ args }}

# Deploy XanV1 behind a UUPS proxy
deploy deployer initial-mint-recipient council chain *args:
    @echo "Cleaning contracts to ensure reproducible build..."
    @just clean
    forge script script/DeployXanV1.s.sol:DeployXanV1 \
        --sig "run(address,address)" {{ initial-mint-recipient }} {{ council }} \
        --broadcast --rpc-url {{ chain }} --account {{ deployer }} {{ args }}

# Simulate deploying governance + preparing the XanV1→V2 upgrade implementation (dry-run). `sender` is the deployer,
# who becomes the transient timelock admin (`run` broadcasts as `msg.sender`).
prepare-upgrade-simulate sender proxy council chain *args:
    @echo "Cleaning contracts to ensure reproducible build..."
    @just clean
    forge script script/PrepareXanV2Upgrade.s.sol:PrepareXanV2Upgrade \
        --sig "run(address,address)" {{ proxy }} {{ council }} \
        --rpc-url {{ chain }} --sender {{ sender }} {{ args }}

# Deploy governance + prepare the XanV1→V2 upgrade implementation. `sender` (the address behind `deployer`) becomes the
# transient timelock admin. The returned `implV2` must then be scheduled by the V1 council multisig via
# `scheduleCouncilUpgrade(implV2)` before running `upgrade`.
prepare-upgrade deployer sender proxy council chain *args:
    @echo "Cleaning contracts to ensure reproducible build..."
    @just clean
    forge script script/PrepareXanV2Upgrade.s.sol:PrepareXanV2Upgrade \
        --sig "run(address,address)" {{ proxy }} {{ council }} \
        --broadcast --rpc-url {{ chain }} --account {{ deployer }} --sender {{ sender }} {{ args }}

# Simulate executing the scheduled XanV1→V2 upgrade (permissionless) (dry-run)
upgrade-simulate proxy chain *args:
    @echo "Cleaning contracts to ensure reproducible build..."
    @just clean
    forge script script/ExecuteXanV2Upgrade.s.sol:ExecuteXanV2Upgrade \
        --sig "run(address)" {{ proxy }} \
        --rpc-url {{ chain }} {{ args }}

# Execute the scheduled XanV1→V2 upgrade (permissionless)
upgrade deployer proxy chain *args:
    @echo "Cleaning contracts to ensure reproducible build..."
    @just clean
    forge script script/ExecuteXanV2Upgrade.s.sol:ExecuteXanV2Upgrade \
        --sig "run(address)" {{ proxy }} \
        --broadcast --rpc-url {{ chain }} --account {{ deployer }} {{ args }}

# --- Verification ---

# Verify an implementation contract on sourcify (e.g. contract=src/XanV1.sol:XanV1)
verify-impl-sourcify address contract chain *args:
    ETHERSCAN_API_KEY="" forge verify-contract {{ address }} {{ contract }} \
        --chain {{ chain }} --verifier sourcify --watch {{ args }}

# Verify an implementation contract on etherscan (e.g. contract=src/XanV1.sol:XanV1)
verify-impl-etherscan address contract chain *args:
    forge verify-contract {{ address }} {{ contract }} \
        --chain {{ chain }} --verifier etherscan --watch {{ args }}

# Verify an implementation contract on a custom explorer
verify-impl-custom address contract chain verifier-url *args:
    forge verify-contract {{ address }} {{ contract }} \
        --chain {{ chain }} --verifier-url {{ verifier-url }} --watch {{ args }}

# Verify an implementation contract on both sourcify and etherscan
verify-impl address contract chain: (verify-impl-sourcify address contract chain) (verify-impl-etherscan address contract chain)

# Verify the ERC1967 proxy on sourcify (encodes the constructor args from the deploy inputs)
verify-proxy-sourcify proxy implementation initial-mint-recipient council chain *args:
    ETHERSCAN_API_KEY="" forge verify-contract {{ proxy }} \
        lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
        --chain {{ chain }} --verifier sourcify --watch \
        --constructor-args "$(cast abi-encode 'c(address,bytes)' {{ implementation }} "$(cast calldata 'initializeV1(address,address)' {{ initial-mint-recipient }} {{ council }})")" {{ args }}

# Verify the ERC1967 proxy on etherscan (encodes the constructor args from the deploy inputs)
verify-proxy-etherscan proxy implementation initial-mint-recipient council chain *args:
    forge verify-contract {{ proxy }} \
        lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
        --chain {{ chain }} --verifier etherscan --watch \
        --constructor-args "$(cast abi-encode 'c(address,bytes)' {{ implementation }} "$(cast calldata 'initializeV1(address,address)' {{ initial-mint-recipient }} {{ council }})")" {{ args }}

# Verify the ERC1967 proxy on a custom explorer (encodes the constructor args from the deploy inputs)
verify-proxy-custom proxy implementation initial-mint-recipient council chain verifier-url *args:
    forge verify-contract {{ proxy }} \
        lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
        --chain {{ chain }} --verifier-url {{ verifier-url }} --watch \
        --constructor-args "$(cast abi-encode 'c(address,bytes)' {{ implementation }} "$(cast calldata 'initializeV1(address,address)' {{ initial-mint-recipient }} {{ council }})")" {{ args }}

# Verify the ERC1967 proxy on both sourcify and etherscan
verify-proxy proxy implementation initial-mint-recipient council chain: (verify-proxy-sourcify proxy implementation initial-mint-recipient council chain) (verify-proxy-etherscan proxy implementation initial-mint-recipient council chain)
