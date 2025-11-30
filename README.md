## Reactive Chainlink Feed Mirror

Mirror a Chainlink price feed from an origin chain to a destination chain using **Reactive Smart Contracts**. The Reactive Network listens for feed updates on the origin chain, then delivers a callback that is exposed as a standard `AggregatorV3Interface` on the destination chain, so any consumer can read the mirrored feed without changing its integration code.

### Components
- `src/FeedReactive.sol` (`ChainlinkFeedMirrorReactive`): reactive contract deployed to the Reactive VM. Subscribes to `AnswerUpdated` logs on the origin feed and emits a `Callback` for each update.
- `src/FeedProxy.sol` (`MirroredPriceFeedCallback`): destination-side callback that implements `AggregatorV3Interface`, stores the mirrored rounds, and emits `FeedUpdated` on every update.
- `src/MockOracle.sol`: simple test oracle that emits `AnswerUpdated` events so you can dry-run the pipeline on a dev network.

### Data Flow (design choices)
1. On deployment, `ChainlinkFeedMirrorReactive` calls `service.subscribe(originChainId, sourceFeed, topic_0, ...)` so the Reactive Network relays only the Chainlink `AnswerUpdated(int256,uint256,uint256)` events you care about.
2. The reactive contract pulls the price from `topic_1`, round ID from `topic_2`, and `updatedAt` from log data. It reuses `roundId` as `answeredInRound` and tracks `startedAt` per round (defaulting to `updatedAt` if missing).
3. The destination callback implements the exact Chainlink `AggregatorV3Interface` (`decimals`, `description`, `version`, `getRoundData`, `latestRoundData`) so downstream consumers can point to the mirrored feed without code changes.
5. **Safety controls** – Only the Reactive system contract can invoke `callback`, enforced by `authorizedSenderOnly` and RVM instance checks in `AbstractCallback` / `AbstractReactive`.

### Repository Layout
- `src/FeedReactive.sol` – reactive listener and callback emitter
- `src/FeedProxy.sol` – on-destination feed storage & Chainlink interface
- `src/MockOracle.sol` – local testing helper
- `lib/reactive-lib` – Reactive Network abstractions (system contract, auth helpers)
- `lib/chainlink-local` – Chainlink aggregator interfaces

### Prerequisites
- Foundry toolchain (`forge`, `cast`, `anvil`)
- Access to an origin RPC (e.g., Sepolia), a destination RPC, and a Reactive VM RPC
- Private keys with funds on each network for deployments and callback gas

### Configuration
Copy `.env.example` to `.env` and fill in the values that match your setup:

- `ORIGIN_RPC` / `ORIGIN_CHAIN_ID` / `ORIGIN_PRIVATE_KEY` – network where the Chainlink feed lives
- `DESTINATION_RPC` / `DESTINATION_CHAIN_ID` / `DESTINATION_PRIVATE_KEY` – network where the mirrored feed will be consumed
- `REACTIVE_RPC` / `REACTIVE_PRIVATE_KEY` – Reactive VM endpoint and deployer key
- `SYSTEM_CONTRACT_ADDR` – Reactive system contract address (typically `0x...fffFfF`)
- `DESTINATION_CALLBACK_PROXY_ADDR` – address allowed to trigger `callback` (Reactive system dispatcher on destination)
- `TOPIC_0` – keccak hash of `AnswerUpdated(int256,uint256,uint256)`
- `ORIGIN_ADDR` – address of the source Chainlink feed on the origin chain
- `CALLBACK_ADDR` – address of the deployed callback contract on the destination chain (used when wiring the reactive contract)
- `REACTIVE_ADDR` – optional address of the reactive contract once deployed (for reference)

### Build
```bash
forge build
```

### Deployment Steps
1) **Deploy the destination callback (Chainlink-compatible proxy)**
```bash
forge create src/FeedProxy.sol:MirroredPriceFeedCallback \
  --rpc-url $DESTINATION_RPC \
  --private-key $DESTINATION_PRIVATE_KEY \
  --constructor-args $DESTINATION_CALLBACK_PROXY_ADDR $ORIGIN_ADDR <decimals> "<description>"
```
- Use the origin feed’s `decimals()` and `description()` values so consumers see identical metadata.

2) **Deploy the reactive listener to the Reactive VM**
```bash
forge create src/FeedReactive.sol:ChainlinkFeedMirrorReactive \
  --rpc-url $REACTIVE_RPC \
  --private-key $REACTIVE_PRIVATE_KEY \
  --constructor-args $SYSTEM_CONTRACT_ADDR $ORIGIN_CHAIN_ID $DESTINATION_CHAIN_ID $ORIGIN_ADDR $TOPIC_0 <callback_address> <decimals> "<description>"
```
- Replace `<callback_address>` with the address from step 1. On deployment, the contract auto-subscribes to the origin feed events (when running against the Reactive Network, not inside the VM copy).

3) **(Optional) Local dry-run with the mock oracle**
- Deploy `MockOracle` to your origin dev chain (e.g., Anvil) and call `emitEvent()` to produce `AnswerUpdated` logs. The Reactive Network should relay them, invoking `callback` on the destination and updating `latestRoundData`.

### How to Read the Mirrored Feed
- Latest values: `cast call <callback_address> "latestRoundData()(uint80,int256,uint256,uint256,uint80)"`
- Historical round: `cast call <callback_address> "getRoundData(uint80)(uint80,int256,uint256,uint256,uint80)" <roundId>`
- Metadata: `cast call <callback_address> "decimals()(uint8)"` and `description()`.

### Testing & Maintenance
- Static checks: `forge fmt` and `forge build`

### Notes
- Only the Reactive system contract is authorized to call `callback`; user transactions cannot mutate the mirrored state.

